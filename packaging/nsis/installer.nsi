Unicode true

!define PRODUCT_NAME "文言文推荐系统"
!define PRODUCT_VERSION "0.2.0"
!define PRODUCT_PUBLISHER "AnomalyCo"

Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "chinese-classical-rec-sys-${PRODUCT_VERSION}-windows.exe"
InstallDir "$PROGRAMFILES64\${PRODUCT_NAME}"
RequestExecutionLevel admin

!ifndef RELEASE_DIR
  !define RELEASE_DIR "flutter_app\build\windows\x64\runner\Release"
!endif

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${RELEASE_DIR}\*"

  CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk" "$INSTDIR\chinese_classical_rec_sys.exe"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\卸载.lnk" "$INSTDIR\uninstall.exe"

  CreateShortCut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\chinese_classical_rec_sys.exe"

  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "UninstallString" "$INSTDIR\uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "DisplayVersion" "${PRODUCT_VERSION}"

  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\*.*"
  RMDir /r "$INSTDIR"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\*.*"
  RMDir "$SMPROGRAMS\${PRODUCT_NAME}"
  Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
SectionEnd
