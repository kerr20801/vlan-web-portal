# 🌐 VMware VLAN Auto Portal (VMware VLAN 批次自動部署與虛擬機開通控制台)

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://microsoft.com/PowerShell)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011%20%7C%20Server-lightgrey.svg)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

專為 VMware vCenter 與單機 ESXi 環境打造的輕量圖形化維運自動化控制台。  
**解決機房維運三大核心痛點**：
1. **網路部署太繁瑣**：新主機上架時，無須在網頁手動點擊 60 次「新增 Port Group」，直接從 Excel 貼上清單，一鍵自動完成整批部署！
2. **網卡切換驗證難**：切換 VM VLAN 後需反覆開啟指令視窗測試，本系統內建 Ping / TCP / UDP 多協定連通性驗證。
3. **新人環境開通慢且無 IP**：克隆母機時常因環境無 DHCP 導致 VM 開機失聯，本系統提供一鍵自動尋找空閒 IP、衝突檢測、RFC 1123 電腦名稱合規校驗與 VMware Tools 即時連線追蹤！

---

## 🌟 三大核心模組與特色

### 📑 分頁一：VLAN 批次建立與主機網路同步 (VLAN Auto Provisioner)
1. **🚀 支援 Excel 批次複製貼上 & 本機草稿自動保存**
   - 支援直接從 Excel 貼上表格資料（以逗號、Tab 或空格分隔），每行一筆。
   - 具備即時格式解析、規則數量統計與視覺化預覽表格。
   - **💾 本機草稿自動暫存**：自動將編輯中的清單寫入本機 LocalStorage，即使誤按 F5 重新整理或關閉瀏覽器，再次開啟依然原封不動！
2. **🔍 主機現況即時比對 (Live Diff) & 斷線續接**
   - 連線後選定目標 ESXi 主機，系統會**自動即時比對該主機上的既有 Port Group**。
   - 預覽表格即時標記：`[🟢 主機已存在 (將略過)]` 或 `[🔵 待建立 (新項目)]`。
   - **🎯 僅部署未完成項目**：提供專屬續接按鈕，一鍵僅挑選尚未建立的項目執行，節省大量部署時間！
3. **🔄 支援「從既有主機複製網路 (Host Network Clone)」與「雙向 CSV 匯出」**
   - 擴充叢集新上架 ESXi 主機時，**無需四處翻找過期的 Excel 檔案**。
   - 一鍵讀取運作中主機的 Standard Switch 與所有 PortGroup (VLAN) 設定，秒速克隆至新主機！
   - **📥 雙向 CSV 匯出**：支援將清單一鍵匯出為 CSV 備份（內建 UTF-8 BOM，保證 Excel 開啟中文不亂碼），部署完成後亦可匯出「執行結果清單」，方便歸檔與維運彙報。
4. **⚡ 自動建立與防呆機制**
   - 若目標主機尚未建立對應的 vSwitch（如 `vSwitch1`），系統會**自動先建立 vSwitch**，再建立 Port Group，並貼心警示實體 Uplink 綁定狀態。
   - 若目標 Port Group 已存在，系統**自動略過 (Skipped)**，具備冪等性 (Idempotent)，保證不會拋出錯誤中斷流程。
   - 嚴格檢驗 802.1Q VLAN 範圍（合法為 `0 ~ 4095`，支援 4095 VGT/Trunk 模式）。
5. **🖥️ 支援單主機或「全集群同步」**
   - 若連線至 vCenter，可指定單一目標 ESXi 主機，亦可選擇 **「🌟 全部主機同步部署」**，一次將新規格推播至所有節點。
   - 亦支援獨立單機 ESXi，無需 vCenter 授權即可使用。

---

### 🔌 分頁二：VM 網卡切換與多協定連通性驗證 (VM Network Switcher & Prober)
1. **二級連動網卡快速切換**：下拉自動連動 vSwitch 與該 Switch 下的所有 VLAN (PortGroup)，秒速切換 VM 網卡。
2. **多通訊協定即時檢驗**：
   - 支援 **Ping (ICMP)**
   - 支援 **SSH (TCP Port 22)**
   - 支援 **RDP (TCP Port 3389)**
   - 支援 **自訂 TCP Port**
   - 支援 **UDP 連通性檢測 / 主動探測 (Active Probing)**
3. **智慧重試緩衝機制**：內建自動重試機制，避免作業系統剛切換網路卡時因短暫震盪或 Windows 防火牆策略而產生誤報。

---

### 👥 分頁三：VM 實驗室一鍵克隆與開通 (VM Lab Provisioner)
1. **RFC 1123 電腦名稱合規校驗 (杜絕 `spec.identity.hostName` 報錯)**：
   - 自動將輸入的 VM 名稱或主機名稱過濾底線 `_`、空格與特殊字元，轉換為符合 RFC 1123 規範之合法 Hostname。
   - **Windows**：自動截斷至 NetBIOS 上限 15 字元以內。
   - **Linux**：自動轉為全小寫並限制 63 字元以內。
2. **智慧固定靜態 IP 解決方案 (預設推薦，開機即能連線)**：
   - 針對多數企業與實驗室 VLAN 無 DHCP 伺服器的痛點，系統**預設採用固定靜態 IP (Static IPv4)**，避免 VM 克隆後開機呈現無 IP 狀態。
   - **⚡ 一鍵自動尋找空閒 IP (`/api/scan-free-ip`)**：後端以高速 ICMP Ping 掃描目標網段（約 200~400ms），自動探測並填入下一個未被佔用的空閒 IP、預設閘道與子網路遮罩。
   - **🔍 即時 IP 衝突檢測 (`/api/check-ip`)**：輸入 IP 後一鍵 Ping 檢驗，秒速標示 🟢 安全無衝突 或 🔴 衝突警告。
   - **智慧推算閘道與遮罩**：輸入 IP 時自動帶出預設閘道（如 `.1`）與 `255.255.255.0` 遮罩。
   - **保留 DHCP 模式**：亦支援 DHCP 自動取得 IP，若切換為 DHCP 會貼心提示環境需備有 DHCP Server。
3. **完整支援 Windows Sysprep 與 Linux OS 自訂規格**：
   - **Windows**：自動填入 `FullName`、`OrgName`、時區代碼與 Workgroup，非交談式自動重設全新 SID，徹底解決 Cmdlet 詢問參數卡住問題。
   - **Linux**：自動相容 Ubuntu、Debian、CentOS、RHEL、Rocky、Alma、SLES、Photon 等多種發行版，並合規配置 DNS 伺服器。
4. **📡 VMware Tools 即時狀態輪詢與連線捷徑**：
   - 勾選自動開機後，部署結果卡片即時啟用背景監控，向 vCenter / VMware Tools 輪詢開機與 IP 配發進度。
   - 取得實體 IP 成功在線後，即時提供 **`📋 複製 SSH 指令` (Linux)** 或 **`📋 複製 RDP 指令` (Windows)**，點擊即可一鍵複製並直接連線！

---

## 🔒 資安與架構優化

* **收緊 CORS 來源**：限制僅允許本機 Localhost 存取，嚴防惡意網頁跨站攻擊本機 API。
* **Session 記憶體管理**：登入憑證僅保留在 PowerShell 背景處理序記憶體中，不寫入本地磁碟明文檔案；隨時可點擊右上角 **「🔌 斷開連線」** 即時註銷。
* **零外部依賴、純原生架構**：
  - **前端**：現代化響應式 HTML5 單頁應用（深色主題、進度條動畫、狀態統計）。
  - **後端**：基於 Windows 原生 .NET `HttpListener` 與 PowerShell 5.1+，**無需安裝 IIS、Node.js、Python 或任何第三方 Web 伺服器**。
  - **可攜式支援 (Portable)**：支援將 PowerCLI 模組直接置於 `Modules/` 目錄，隨身碟即插即用，適合不能連線外網的封閉機房跳板機。

---

## 📁 專案架構

```text
VLAN_Web_Portal/
  ├── Modules/                  # VMware PowerCLI 可攜式核心模組 (可選，離線環境使用)
  ├── index.html                # 前端控制台介面 (含 LocalStorage 暫存、主機 Diff、CSV 匯出、IP 工具)
  ├── server.ps1                # 本機輕量 Web 伺服器與 RESTful API (安全強化、純 ASCII 相容)
  ├── vlan_assign_backend.ps1   # VM 網卡切換與多通訊協定連通性檢驗腳本
  ├── 啟動服務.bat              # Windows 一鍵啟動批次檔
  ├── setup_modules.bat         # 一鍵下載 PowerCLI 模組 (若是從 Git clone 下來)
  ├── 使用說明.txt              # 詳細文字操作指南
  ├── README.md                 # 專案說明文件
  └── LICENSE                   # MIT 開源授權協議
```

---

## 🚀 快速開始

### 方式一：從 Release 下載綠色免安裝包（最推薦）
1. 解壓縮後雙擊 `啟動服務.bat`。
2. 預設瀏覽器會自動彈出控制台頁面（`http://localhost:8899/`）。
3. 點擊右上角 **⚙️ 尚未連線** 輸入 vCenter 或 ESXi 帳密。
4. 依照您的需求切換不同分頁：
   - **分頁 1**：選擇主機 ➡️ 貼上清單 ➡️ 即時比對 ➡️ 點擊「立即執行批次部署」！
   - **分頁 2**：選取 VM ➡️ 下拉切換 VLAN ➡️ 點擊「切換並驗證網路連通性」！
   - **分頁 3**：選取範本 VM ➡️ 點擊「⚡ 自動尋找空閒 IP」➡️ 點擊「🚀 立即執行克隆與自動配網」！

### 方式二：從 Git Clone 自行建置
1. 複製本儲存庫：
   ```bash
   git clone https://github.com/kerr20801/vlan-web-portal.git
   cd vlan-web-portal
   ```
2. 執行 `setup_modules.bat` 下載相依模組（若本機已全域安裝 PowerCLI 可跳過此步）。
3. 雙擊 `啟動服務.bat` 即可開始使用！

---

## 📋 批次部署格式範例

在分頁 1 輸入框中，每一行代表一個 Port Group 規則，格式為：  
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

# 軟體路由器或防火牆 (Trunk 模式)
vSwitch1, VLAN-Trunk-All, 4095
```

---

## 👨‍💻 作者 (Author)
* **Kerr** ([@kerr20801](https://github.com/kerr20801))

---

## 📄 License
MIT License. 歡迎自由修改、分發與用於企業內部維運。
