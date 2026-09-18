# iPhone Cam - Wireless OBS Camera for TrollStore (iOS 15.5)

แอปสตรีมกล้อง iPhone 6S (iOS 15.5) ความละเอียดสูง (สูงสุด 4K / 1080p) ส่งสัญญาณภาพผ่าน Wi-Fi เข้าคอมพิวเตอร์เพื่อใช้อัดคลิปหรือสตรีมบน **OBS Studio** ได้โดยตรง ไม่ต้องมีสาย ไม่ต้องมีใบรับรอง Apple Developer (ติดตั้งผ่าน TrollStore ได้ถาวร) และมี **GitHub Actions** สำหรับ Build ไฟล์ `.ipa` อัตโนมัติ

---

## ฟีเจอร์หลัก (Features)
- 🔄 **สลับกล้องหน้า/หลังได้ทันที**: กล้องหลังรองรับความละเอียดสูงสุดถึง **4K UHD** หรือ **1080p 60fps** / กล้องหน้ารองรับ **720p HD**
- 📱 **ล็อคแนวนอน (Landscape)**: ปรับ Sensor กล้องให้ภาพเข้า OBS ในแนวระนาบ 16:9 พอดีจอ ไม่กลับหัว
- ⚡ **Zero-Lag & Frame-Drop**: ออกแบบระบบ Streaming สำหรับ Live โดยเฉพาะ ไม่เกิดปัญหาดีเลย์สะสมเมื่อสัญญาณ Wi-Fi กระตุก
- 🌐 **OBS-Ready (2 รูปแบบ)**:
  - **Browser Source**: เปิด `http://<IP-iPhone>:8080/` (มีระบบ Responsive Auto-fit สวยงาม)
  - **Media Source / VLC Source**: เปิด `http://<IP-iPhone>:8080/stream.mjpg`
- 🔋 **Always On**: ปิดระบบพักหน้าจออัตโนมัติขณะเปิดแอป หน้าจอไม่ดับระหว่างอัดคลิป
- 🎛️ **On-Screen HUD**: แตะที่หน้าจอเพื่อซ่อน/แสดงแถบควบคุม (ปุ่มสลับกล้อง, ตัวเลือกความละเอียด, สไลเดอร์ปรับคุณภาพภาพ)

---

## ขั้นตอนการ Build ไฟล์ `.ipa` ผ่าน GitHub Actions

คุณสามารถนำโค้ดนี้ขึ้น GitHub เพื่อให้ GitHub Actions บิลด์เป็นไฟล์ `.ipa` ให้โดยอัตโนมัติ:

1. **สร้าง Git Repository**:
   เปิด Terminal หรือ PowerShell ในโฟลเดอร์นี้ แล้วสั่ง:
   ```bash
   git init
   git add .
   git commit -m "Initial commit for iPhoneCam"
   ```

2. **Push ขึ้น GitHub Repository ส่วนตัว**:
   - ไปที่ [GitHub](https://github.com/new) สร้าง Repository ใหม่ (ตั้งเป็น Public หรือ Private ก็ได้)
   - เชื่อมต่อและ Push:
     ```bash
     git remote add origin https://github.com/<USERNAME>/<REPO-NAME>.git
     git branch -M main
     git push -u origin main
     ```

3. **ดาวน์โหลดไฟล์ `.ipa`**:
   - เข้าไปที่แท็บ **Actions** บน GitHub ของคุณ
   - รอ Workflow ชื่อ `Build TrollStore IPA` ทำงานเสร็จ (ประมาณ 1-2 นาที)
   - คลิกเข้าไปในผลการรันล่าสุด เลื่อนลงมาด้านล่างสุดที่หัวข้อ **Artifacts**
   - ดาวน์โหลดไฟล์ `iPhoneCam-ipa.zip` แตกไฟล์ออกมาจะได้ `iPhoneCam.ipa` ทันที!

---

## ขั้นตอนการติดตั้งบน iPhone 6S (TrollStore)

1. ส่งไฟล์ `iPhoneCam.ipa` เข้า iPhone 6S ของคุณ (ผ่าน AirDrop, Telegram, Google Drive หรือเว็บเบราว์เซอร์)
2. เปิดไฟล์ `.ipa` แล้วเลือก **Share -> TrollStore**
3. กด **Install** ใน TrollStore
4. เปิดแอป **iPhone Cam** จากหน้าโฮม และอนุญาตสิทธิ์การใช้งาน:
   - สิทธิ์กล้อง (Camera Permission)
   - สิทธิ์เครือข่ายภายในบ้าน (Local Network Permission)

---

## ขั้นตอนการตั้งค่าใน OBS Studio บนคอมพิวเตอร์

> **ข้อกำหนดเบื้องต้น**: iPhone และ Laptop ต้องต่อ Wi-Fi วงเดียวกัน (หรือเปิด Personal Hotspot จาก iPhone ให้ Laptop ต่อก็ได้)

เมื่อเปิดแอปบน iPhone คุณจะเห็นที่อยู่ URL ปรากฏอยู่ด้านบน เช่น `http://192.168.1.50:8080`

### วิธีที่ 1: ใช้ Browser Source (แนะนำ - ง่ายที่สุด)
1. ใน OBS Studio ตรงกล่อง **Sources** ให้กด `+` แล้วเลือก **Browser**
2. ตั้งชื่อ เช่น `iPhone Cam`
3. ในช่อง **URL**: ใส่ `http://<IP-iPhone>:8080/` (เช่น `http://192.168.1.50:8080/`)
4. ตั้งขนาด:
   - **Width**: `1920` (หรือ `3840` หากเลือก 4K)
   - **Height**: `1080` (หรือ `2160` หากเลือก 4K)
5. ติ๊กถูกที่ **Shutdown source when not visible**
6. กด **OK** ภาพจะขึ้นมาทันที!

### วิธีที่ 2: ใช้ Media Source (ใช้ Hardware Video Decoding)
1. ใน OBS Studio ตรงกล่อง **Sources** ให้กด `+` แล้วเลือก **Media Source**
2. **เอาเครื่องหมายถูกออก** จากช่อง **Local File**
3. ในช่อง **Input**: ใส่ `http://<IP-iPhone>:8080/stream.mjpg`
4. ในช่อง **Input Format**: พิมพ์ `mjpeg`
5. กด **OK**

---

## คำแนะนำเรื่องความละเอียดและประสิทธิภาพ (iPhone 6S)
- **1080p FHD (แนะนำ)**: เหมาะที่สุดสำหรับการสตรีมต่อเนื่อง เครื่องไม่ร้อน แบตเตอรี่ไม่หมดไว และได้ 30-60 FPS ลื่นไหล
- **4K UHD**: ชิป Apple A9 ใน iPhone 6S รองรับการถ่าย 4K ได้ แต่การสตรีม 4K แบบสดจะใช้ทรัพยากร CPU/Wi-Fi สูง แนะนำให้เสียบสายชาร์จขณะใช้งาน
- แตะที่หน้าจอ 1 ครั้งเพื่อซ่อนเมนูและปุ่มควบคุมทั้งหมด จะได้ภาพพรีวิวเต็มจอสะอาดตา
