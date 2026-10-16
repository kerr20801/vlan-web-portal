# 🌐 VMware VLAN Auto Portal (VMware VLAN 批次自動部署與切換控制台)

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://microsoft.com/PowerShell)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011%20%7C%20Server-lightgrey.svg)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

專為 VMware vCenter 與單機 ESXi 環境打造的輕量圖形化網路管理工具。  
**解決機房痛點**：上架新主機時，無須在網頁手動點擊 60 次「新增 Port Group」，直接從 Excel 貼上清單，一鍵自動完成整批部署！

---

## 🌟 核心特色

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

6. **👥 虛擬機自動克隆與配網 (VM Lab Provisioner / 新人環境一鍵開通)**
   - 選取母體 VM 範本（Windows Server / Win11 / Linux），透過 vCenter 原生自訂規格 (OS Customization) 自動套用新電腦名稱、全新 SID 與靜態 IPv4。
   - 免去每次新人到職都要資深人員花半小時手動 Clone、登入主機改 IP 的繁瑣流程，一鍵完成開通並自動開機！

7. **🔌 VM 網卡切換與多協定連通性驗證**
   - 整合虛擬機網卡快速切換功能（支援多 vSwitch/VLAN 二級連動下拉選單）。
   - **多協定連通性檢測**：支援 **Ping (ICMP)**、**RDP (Port 3389)**、**SSH (Port 22)** 與 **自訂 TCP Port**，含 3 次自動重試緩衝，徹底解決 Windows VM 檢驗誤報問題。

8. **🔒 安全性與 Session 管理**
   - **收緊 CORS 來源**：限制僅允許本機 Localhost 存取，嚴防惡意網頁跨站攻擊本機 API。
   - **🔌 斷開連線 (登出)**：支援一鍵中斷連線並釋放背景記憶體中快取的 Session 與認證資料。

9. **📦 零外部依賴、純原生架構**
   - **前端**：現代化響應式 HTML5 單頁應用（支援深色主題、進度條動畫、狀態統計）。
   - **後端**：基於 Windows 原生 .NET `HttpListener`，**無需安裝 IIS、Node.js、Python 或任何第三方 Web 伺服器**。
   - **可攜式支援 (Portable)**：支援將 PowerCLI 模組直接置於 `Modules/` 目錄，隨身碟即插即用，適合不能連線外網的封閉機房跳板機。

---

## 📁 專案架構

```text
VLAN_Web_Portal/
  ├── Modules/                  # VMware PowerCLI 可攜式核心模組 (可選，離線環境使用)
  ├── index.html                # 前端控制台介面 (含 LocalStorage 暫存、主機 Diff、CSV 匯出)
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
4. 選擇目標主機 ➡️ 貼上清單（或由主機克隆） ➡️ 預覽表即時檢視主機現況 ➡️ 點擊 **「⚡ 立即執行批次部署」**！

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

# 軟體路由器或防火牆 (Trunk 模式)
vSwitch1, VLAN-Trunk-All, 4095
```

---

## 🔒 資安說明
* 登入之主機帳號與密碼**僅保留在當前運行的 PowerShell 行程記憶體中**。
* 隨時可點擊右上角 **「🔌 斷開連線」** 即時釋放 Session。
* 本機 Web 伺服器嚴格限制來源，不會在本地磁碟留下任何文字明文密碼檔。

---

## 👨‍💻 作者 (Author)
* **Kerr** ([@kerr20801](https://github.com/kerr20801))

---

## 📄 License
MIT License. 歡迎自由修改、分發與用於企業內部維運。
