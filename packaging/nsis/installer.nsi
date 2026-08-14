Unicode true

!include "MUI2.nsh"
!include "FileFunc.nsh"

!define PRODUCT_NAME "文言文推荐系统"
!define PRODUCT_VERSION "0.10.2"
!define PRODUCT_PUBLISHER "AnomalyCo"

; ── MUI2 界面配置 ──────────────────────────────────────────────────────────
; 安装包本体/卸载器图标（BMP 帧 .ico，16/32/48，NSIS 全版本兼容）
; 注意：Icon 相对脚本所在目录解析；CI 从仓库根调用时 ${__FILEDIR__}
; 会展开为相对路径导致 packaging\nsis\packaging\nsis 重复，故用单段路径
!define MUI_ICON "app_icon.ico"
!define MUI_UNICON "app_icon.ico"

; 安装/卸载过程中点取消时弹确认框
!define MUI_ABORTWARNING
; 完成页提供"立即运行"，默认不勾选
!define MUI_FINISHPAGE_RUN "$INSTDIR\chinese_classical_rec_sys.exe"
!define MUI_FINISHPAGE_RUN_TEXT "立即运行 $(^Name)"
!define MUI_FINISHPAGE_RUN_NOTCHECKED

Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "chinese-classical-rec-sys-${PRODUCT_VERSION}-windows.exe"
; 尾斜杠：否则用户在目录选择页"新建文件夹并选中"时会被追加一层产品名
InstallDir "$PROGRAMFILES64\${PRODUCT_NAME}\"
; 升级/重装时记住用户上次选择的目录（卸载会清掉该键，卸载后重装回默认值）
InstallDirRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "InstallLocation"
RequestExecutionLevel admin


; ── 页面 ────────────────────────────────────────────────────────────────────
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; ── 语言（仅简体中文）───────────────────────────────────────────────────────
!insertmacro MUI_LANGUAGE "SimpChinese"

; ── 安装包 exe 版本信息（属性页 / UAC 弹窗显示友好名称）───────────────────
; bump_version.sh 发布时同步为 X.Y.Z.0
VIProductVersion "0.10.2.0"
VIAddVersionKey "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey "FileDescription" "${PRODUCT_NAME} 安装程序"
VIAddVersionKey "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "LegalCopyright" "© ${PRODUCT_PUBLISHER}"

Section "Install"
  ; 每机器安装（HKLM 注册表项），快捷方式放 All Users 开始菜单/桌面
  SetShellVarContext all
  SetOutPath "$INSTDIR"
  File /r "${RELEASE_DIR}\*"

  CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk" "$INSTDIR\chinese_classical_rec_sys.exe"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\卸载.lnk" "$INSTDIR\uninstall.exe"

  CreateShortCut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\chinese_classical_rec_sys.exe"

  ; 控制面板"程序和功能"卸载信息
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "DisplayIcon" "$INSTDIR\chinese_classical_rec_sys.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "UninstallString" "$INSTDIR\uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "InstallLocation" "$INSTDIR"
  WriteRegDWord HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "NoModify" "1"
  WriteRegDWord HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "NoRepair" "1"
  ; 已安装体积（KB），控制面板显示真实大小
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWord HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "EstimatedSize" "$0"

  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
  SetShellVarContext all
  Delete "$INSTDIR\*.*"
  RMDir /r /REBOOTOK "$INSTDIR"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\*.*"
  RMDir "$SMPROGRAMS\${PRODUCT_NAME}"
  Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
SectionEnd
