# การแสดงผล ClaudeBar บน Touch Bar (MacBook Pro M1)

คู่มือนี้แนะนำวิธีการนำข้อมูลโควต้าจาก ClaudeBar มาแสดงผลบนแถบ Touch Bar ของ MacBook Pro 13" (M1 / M2) แบบค้างไว้ตลอดเวลา โดยใช้ **BetterTouchTool (BTT)** หรือ **MTMR**

---

## สารบัญ
1. [การทำงาน](#การทำงาน)
2. [วิธีที่ 1: ติดตั้งผ่าน BetterTouchTool (แนะนำ)](#วิธีที่-1-ติดตั้งผ่าน-bettertouchtool-แนะนำ)
3. [วิธีที่ 2: ติดตั้งผ่าน MTMR (ฟรีและ Open Source)](#วิธีที่-2-ติดตั้งผ่าน-mtmr-ฟรีและ-open-source)
4. [คำสั่งลัด (URL Scheme)](#คำสั่งลัด-url-scheme)
5. [การแก้ปัญหา (Troubleshooting)](#การแก้ปัญหา-troubleshooting)

---

## การทำงาน

ClaudeBar จะทำการ sync ข้อมูลโควต้าล่าสุดลงในไฟล์ `~/.claudebar/status.json` โดยอัตโนมัติทุกครั้งที่:
- สถานะโควต้าเปลี่ยน
- มีการรีเฟรชโควต้า
- มีการสลับ Provider

สคริปต์ [scripts/touchbar_status.py](file:///Users/jzd101/Documents/ClaudeBar/scripts/touchbar_status.py) จะอ่านไฟล์นี้และแปลงผลเป็นสี, รูปไอคอนจริงของ Provider และข้อความสำหรับ Touch Bar โดยใช้ CPU และแบตเตอรี่แทบจะเป็น 0

### รูปไอคอนจริงของ Provider (Real Provider Icons)
รูปภาพไอคอนจริงของแต่ละ Provider (PNG แบบ Transparent) ถูกรวบรวมไว้ที่ `scripts/icons/` และ `~/.claudebar/icons/` ครบทุกค่าย:
- **Claude** (Anthropic)
- **OpenAI / Codex**
- **Google Gemini**
- **GitHub Copilot**
- **Cursor**
- **DeepSeek**
- **Alibaba Qwen**
- **Google Antigravity**
- **xAI Grok**
- **AWS Bedrock**
- **Moonshot Kimi**
- **MiniMax**
- **Mistral**
- **Z.ai**
- **Vercel**, **AmpCode**, **OpenCode**, **Oh My Pi**, **Kiro**

เมื่อรันด้วยคำสั่ง `--btt` สคริปต์จะส่ง `icon_path` ชี้ไปยังไฟล์รูปจริงของ Provider นั้นๆ ให้ BetterTouchTool นำไปเรนเดอร์บน Touch Bar ทันที

---

## วิธีที่ 1: ติดตั้งผ่าน BetterTouchTool (แนะนำ)

BetterTouchTool (BTT) สามารถแสดง Widget บน Touch Bar ค้างไว้ตลอดเวลา พร้อมเปลี่ยนสีพื้นหลังตามสถานะ (เขียว/ส้ม/แดง)

### ขั้นตอนการตั้งค่า:

1. เปิดแอพ **BetterTouchTool**
2. เลือกแท็บ **Touch Bar** ที่เมนูด้านบน
3. เลือก **All Apps** ในคอลัมน์ซ้ายสุด (เพื่อให้แสดงผลในทุกโปรแกรม)
4. กดปุ่ม **+ (Add Widget)** ที่แถบด้านล่าง
5. ค้นหาและเลือก **"Shell Script / Task Widget"**
6. ตั้งค่า Widget ดังนี้:
   - **Widget Name**: `ClaudeBar Quota`
   - **Execute every**: `10` seconds (หรือตามต้องการ)
   - **Script / Task**:
     ```bash
     python3 /Users/jzd101/Documents/ClaudeBar/scripts/touchbar_status.py --btt
     ```
   - **Script Output Type**: เลือก **`JSON (text, background_color, font_color)`**
7. **ตั้งค่าเมื่อแตะที่ปุ่ม (Assign Action)**:
   - ในช่อง **Action** ให้เลือก **"Execute Terminal Command"** หรือ **"Open URL"**
   - URL: `claudebar://open` (เปิดเมนู ClaudeBar) หรือ `claudebar://refresh` (สั่งรีเฟรชโควต้าทันที)

---

## วิธีที่ 2: ติดตั้งผ่าน MTMR (ฟรีและ Open Source)

[MTMR (My TouchBar. My Rules.)](https://github.com/Toxblh/MTMR) เป็นแอพพลิเคชันฟรีแบบ Open Source สำหรับจัดการ Touch Bar ผ่านไฟล์ JSON

### ขั้นตอนการตั้งค่า:

1. ติดตั้ง MTMR (ผ่าน brew: `brew install --cask mtmr`)
2. เปิดไฟล์ตั้งค่า `~/Library/Application Support/MTMR/items.json`
3. เพิ่มโค้ด Widget ด้านล่างลงใน Array:

```json
{
  "type": "shellStream",
  "width": 140,
  "bordered": true,
  "align": "right",
  "refreshInterval": 10,
  "commandPath": "/usr/bin/python3",
  "shellArguments": [
    "/Users/jzd101/Documents/ClaudeBar/scripts/touchbar_status.py",
    "--mtmr"
  ],
  "actions": [
    {
      "trigger": "singleTap",
      "action": "openUrl",
      "url": "claudebar://open"
    }
  ]
}
```

4. บันทึกไฟล์ และ Touch Bar จะอัปเดตทันที

---

## คำสั่งลัด (URL Scheme)

ClaudeBar รองรับ URL Scheme ต่อไปนี้:

| URL Scheme | คำอธิบาย | ตัวอย่างการเรียกใน Terminal |
|---|---|---|
| `claudebar://open` | เปิดหน้าต่างเมนู ClaudeBar | `open claudebar://open` |
| `claudebar://refresh` | สั่ง Refresh โควต้าของทุก Provider ทันที | `open claudebar://refresh` |
| `claudebar://settings` | เปิดหน้าต่างการตั้งค่า (Settings) | `open claudebar://settings` |

---

## การเปิด/ปิด Touch Bar Integration

คุณสามารถเปิดหรือปิดการส่งออกข้อมูล Touch Bar ได้จาก:
- เข้าไปที่ **Settings (Cmd + ,) > General > Touch Bar**
- หากสวิตช์ปิดอยู่:
  - `status.json` จะระบุสถานะเป็น `disabled`
  - สคริปต์ BetterTouchTool (`--btt`) จะซ่อน Widget ให้โปร่งแสง (ไม่เกะกะแถบ Touch Bar)
  - สคริปต์ MTMR (`--mtmr`) จะไม่แสดงข้อความใดๆ

---

## การแก้ปัญหา (Troubleshooting)

* **Touch Bar ขึ้นว่า "ClaudeBar: Offline"**:
  - ตรวจสอบว่าเปิดแอพ ClaudeBar อยู่หรือไม่
  - ตรวจสอบว่ามีไฟล์ `~/.claudebar/status.json` อยู่จริงหรือไม่
* **ทดสอบรันสคริปต์ด้วยตนเอง**:
  ```bash
  python3 scripts/touchbar_status.py --btt
  python3 scripts/touchbar_status.py --mtmr
  ```
