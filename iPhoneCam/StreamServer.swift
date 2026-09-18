import Foundation
import Network

final class StreamClient {
    let id = UUID()
    let connection: NWConnection
    var isSending = false
    
    init(connection: NWConnection) {
        self.connection = connection
    }
}

final class StreamServer: ObservableObject {
    @Published var isRunning = false
    @Published var connectedClientsCount = 0
    @Published var port: UInt16 = 8080
    
    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "com.hobby.iphonecam.server", qos: .userInteractive)
    private var clients: [UUID: StreamClient] = [:]
    private let clientsLock = NSLock()
    
    init(port: UInt16 = 8080) {
        self.port = port
    }
    
    func start() {
        serverQueue.async { [weak self] in
            self?.setupListener()
        }
    }
    
    func stop() {
        serverQueue.async { [weak self] in
            guard let self = self else { return }
            self.listener?.cancel()
            self.listener = nil
            
            self.clientsLock.lock()
            for client in self.clients.values {
                client.connection.cancel()
            }
            self.clients.removeAll()
            self.clientsLock.unlock()
            
            DispatchQueue.main.async {
                self.isRunning = false
                self.connectedClientsCount = 0
            }
        }
    }
    
    private func setupListener() {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: self.port) ?? 8080)
            self.listener = listener
            
            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self.isRunning = true
                        print("StreamServer ready on port \(self.port)")
                    case .failed(let error):
                        print("StreamServer failed: \(error)")
                        self.isRunning = false
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }
            
            listener.newConnectionHandler = { [weak self] newConnection in
                self?.handleNewConnection(newConnection)
            }
            
            listener.start(queue: serverQueue)
        } catch {
            print("Failed to initialize listener: \(error)")
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: serverQueue)
        readHttpRequest(on: connection)
    }
    
    private func readHttpRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 2048) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("HTTP read error: \(error)")
                connection.cancel()
                return
            }
            
            guard let data = data, let request = String(data: data, encoding: .utf8) else {
                if isComplete {
                    connection.cancel()
                }
                return
            }
            
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            
            if firstLine.contains("GET / ") || firstLine.contains("GET /index.html") {
                self.serveWebPlayer(on: connection)
            } else {
                // Stream endpoint (/stream.mjpg, /video.mjpg, or any other path)
                self.startMjpegStream(on: connection)
            }
        }
    }
    
    private func serveWebPlayer(on connection: NWConnection) {
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>iPhone Cam Stream</title>
            <style>
                * { box-sizing: border-box; margin: 0; padding: 0; }
                html, body {
                    width: 100vw;
                    height: 100vh;
                    background-color: #000;
                    overflow: hidden;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                }
                img {
                    width: 100%;
                    height: 100%;
                    object-fit: contain;
                }
            </style>
        </head>
        <body>
            <img id="stream" src="/stream.mjpg" alt="Live Camera Stream">
            <script>
                // Auto-reconnect if connection drops
                const img = document.getElementById('stream');
                img.onerror = function() {
                    setTimeout(() => {
                        img.src = '/stream.mjpg?t=' + Date.now();
                    }, 1000);
                };
            </script>
        </body>
        </html>
        """
        
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n"
        let responseData = (header + html).data(using: .utf8) ?? Data()
        
        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    private func startMjpegStream(on connection: NWConnection) {
        let header = "HTTP/1.1 200 OK\r\n" +
                     "Server: iPhoneCam\r\n" +
                     "Connection: close\r\n" +
                     "Cache-Control: no-store, no-cache, must-revalidate, pre-check=0, post-check=0, max-age=0\r\n" +
                     "Pragma: no-cache\r\n" +
                     "Content-Type: multipart/x-mixed-replace; boundary=--frame\r\n\r\n"
        
        guard let headerData = header.data(using: .utf8) else {
            connection.cancel()
            return
        }
        
        connection.send(content: headerData, completion: .contentProcessed({ [weak self] error in
            guard let self = self else { return }
            if let error = error {
                print("Failed to send MJPEG header: \(error)")
                connection.cancel()
                return
            }
            
            let client = StreamClient(connection: connection)
            self.clientsLock.lock()
            self.clients[client.id] = client
            let count = self.clients.count
            self.clientsLock.unlock()
            
            DispatchQueue.main.async {
                self.connectedClientsCount = count
            }
        }))
    }
    
    /// Broadcast a new JPEG frame to all connected clients.
    /// Uses frame-dropping to guarantee ultra-low latency without network buffering lag.
    func sendFrame(_ jpegData: Data) {
        clientsLock.lock()
        let activeClients = Array(clients.values)
        clientsLock.unlock()
        
        guard !activeClients.isEmpty else { return }
        
        let headerString = "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpegData.count)\r\n\r\n"
        guard let headerData = headerString.data(using: .utf8) else { return }
        
        var fullPacket = Data()
        fullPacket.reserveCapacity(headerData.count + jpegData.count + 2)
        fullPacket.append(headerData)
        fullPacket.append(jpegData)
        fullPacket.append(contentsOf: [0x0D, 0x0A]) // \r\n
        
        for client in activeClients {
            // Drop frame for this client if it is still sending previous frame
            guard !client.isSending else { continue }
            client.isSending = true
            
            client.connection.send(content: fullPacket, completion: .contentProcessed({ [weak self, weak client] error in
                guard let client = client else { return }
                client.isSending = false
                
                if let error = error {
                    // Remove disconnected client
                    self?.removeClient(client.id)
                }
            }))
        }
    }
    
    private func removeClient(_ id: UUID) {
        clientsLock.lock()
        if let client = clients.removeValue(forKey: id) {
            client.connection.cancel()
        }
        let count = clients.count
        clientsLock.unlock()
        
        DispatchQueue.main.async {
            self.connectedClientsCount = count
        }
    }
}
