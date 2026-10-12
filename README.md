# 🌐 VMware VLAN Auto Portal (VMware VLAN 批次自動部署與切換控制台)

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://microsoft.com/PowerShell)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011%20%7C%20Server-lightgrey.svg)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

專為 VMware vCenter 與單機 ESXi 環境打造的輕量圖形化網路管理工具。  
**解決機房痛點**：上架新主機時，無須在網頁手動點擊 60 次「新增 Port Group」，直接從 Excel 貼上清單，一鍵自動完成整批部署！

---

## 🌟 核心特色

1. **🚀 支援 Excel 批次複製貼上**
   - 支援直接從 Excel 貼上表格資料（以逗號、Tab 或空格分隔），每行一筆。
   - 具備即時格式解析、規則數量統計與視覺化預覽表格。

2. **⚡ 自動建立與防呆機制**
   - 若目標主機尚未建立對應的 vSwitch（如 `vSwitch1`），系統會**自動先建立 vSwitch**，再建立 Port Group。
   - 若目標 Port Group 已存在，系統**自動略過 (Skipped)**，具備冪等性 (Idempotent)，保證不會拋出錯誤中斷流程。

3. **🖥️ 支援單主機或「全集群同步」**
   - 若連線至 vCenter，可指定單一目標 ESXi 主機，亦可選擇 **「🌟 全部主機同步部署」**，一次將新規格推播至所有節點。
   - 亦支援獨立單機 ESXi，無需 vCenter 授權即可使用。

4. **📦 零外部依賴、純原生架構**
   - **前端**：現代化響應式 HTML5 單頁應用（支援深色主題、進度條動畫、狀態統計）。
   - **後端**：基於 Windows 原生 .NET `HttpListener`，**無需安裝 IIS、Node.js、Python 或任何第三方 Web 伺服器**。
   - **可攜式支援 (Portable)**：支援將 PowerCLI 模組直接置於 `Modules/` 目錄，隨身碟即插即用，適合不能連線外網的封閉機房跳板機。

5. **🔌 VM 網卡切換與連通性驗證**
   - 整合虛擬機網卡快速切換功能（支援多 vSwitch/VLAN 二級連動下拉選單）。
   - 切換後自動發起 TCP Port 22 (SSH) 連通性驗證，即時回傳網路是否生效。

---

## 📁 專案架構

```text
VLAN_Web_Portal/
  ├── Modules/                  # VMware PowerCLI 可攜式核心模組 (可選，離線環境使用)
  ├── index.html                # 前端控制台介面
  ├── server.ps1                # 本機輕量 Web 伺服器與 RESTful API (純 ASCII 相容)
  ├── vlan_assign_backend.ps1   # VM 網卡切換後端執行腳本
  ├── 啟動服務.bat              # Windows 一鍵啟動批次檔
  ├── setup_modules.bat         # 一鍵下載 PowerCLI 模組 (若是從 Git clone 下來)
  ├── README.md                 # 專案說明文件
  └── LICENSE                   # MIT 開源授權協議
```

---

## 🚀 快速開始

### 方式一：從 Release 下載綠色免安裝包（最推薦）
1. 解壓縮後雙擊 `啟動服務.bat`。
2. 預設瀏覽器會自動彈出控制台頁面（`http://localhost:8899/`）。
3. 點擊右上角 **⚙️ 尚未連線** 輸入 vCenter 或 ESXi 帳密。
4. 選擇目標主機 ➡️ 貼上清單 ➡️ 點擊 **「⚡ 立即執行批次部署」**！

### 方式二：從 Git Clone 自行建置
1. 複製本儲存庫：
   ```bash
   git clone https://github.com/your-username/vlan-web-portal.git
   cd vlan-web-portal
   ```
2. 執行 `setup_modules.bat` 下載相依模組（若本機已全域安裝 PowerCLI 可跳過此步）。
3. 雙擊 `啟動服務.bat` 即可開始使用！

---

## 📋 批次部署格式範例

在網頁輸入框中，每一行代表一個 Port Group 規則，格式為：  
`vSwitch名稱, PortGroup名稱, VLAN_ID`

```text
# 管理與業務網路
vSwitch0, VLAN10-Mgmt, 10
vSwitch0, VLAN20-Dev, 20
vSwitch0, VLAN30-QA, 30

# 應用與資料庫網路
vSwitch1, VLAN100-WebTier, 100
vSwitch1, VLAN101-AppTier, 101
vSwitch1, VLAN200-DBCluster, 200
```

---

## 🔒 資安說明
* 登入之主機帳號與密碼**僅保留在當前運行的 PowerShell 行程記憶體中**。
* 不會在本地磁碟留下任何文字設定檔或歷史憑證，關閉後端服務視窗後立即全數釋放。

---

## 📄 License
MIT License. 歡迎自由修改、分發與用於企業內部維運。
