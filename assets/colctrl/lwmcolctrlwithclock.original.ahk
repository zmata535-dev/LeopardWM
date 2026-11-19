#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent(true)

; --- CONFIGURATION ---
Width            := 140                          ; Extended width (bigger wings at both sides)
Height           := 18                           ; Clock height
NormalX          := (A_ScreenWidth / 2) - (Width / 2) ; Centered horizontally at top
NormalY          := 0                            ; Flush to top edge
DodgeX           := NormalX + 120                ; X-position when dodged
MaxOpacity       := 175                          ; Peak opacity in the center (0 = transparent, 255 = solid)
FadeRatio        := 0.35                         ; Fraction of width for side fade (0.35 = outer 35% on each side fades)
BgColor          := "000011"                     ; Plate background color (Hex RGB)
TextColor        := "FFFFFF"                     ; Clock text color (Hex RGB)
FontName         := "Segoe UI"                   ; Clock font family
FontSize         := 9                            ; Font size in points
TimeFormat       := "HH:mm"                      ; Time format (e.g. "HH:mm" or "HH:mm:ss")
EnableDodge      := true                         ; Dodge mouse pointer when near clock
EnableHotCorners := true                         ; Enable screen corner/edge actions (colctrl, centering, column focus)
; ---------------------

; --- COLOR PARSING & PREPARATION ---
ParseColor(c) {
    if Type(c) = "String"
        return Integer("0x" . StrReplace(c, "#", ""))
    return c
}

bgInt := ParseColor(BgColor)
BgR := (bgInt >> 16) & 0xFF
BgG := (bgInt >> 8) & 0xFF
BgB := bgInt & 0xFF

textInt := ParseColor(TextColor)
TextR := (textInt >> 16) & 0xFF
TextG := (textInt >> 8) & 0xFF
TextB := textInt & 0xFF

; --- GDI+ INITIALIZATION ---
gdiToken := 0
si := Buffer(24, 0)
NumPut("UInt", 1, si, 0)
DllCall("gdiplus\GdiplusStartup", "Ptr*", &gdiToken, "Ptr", si, "Ptr", 0)

; Create Layered GUI window (always-on-top, frameless, no taskbar button)
ClockGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000") ; WS_EX_LAYERED

; Setup 32-bit ARGB Memory DC & DIB Section
hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)

bi := Buffer(40, 0)
NumPut("UInt", 40, bi, 0)
NumPut("Int", Width, bi, 4)
NumPut("Int", -Height, bi, 8) ; Top-down DIB
NumPut("UShort", 1, bi, 12)
NumPut("UShort", 32, bi, 14)

ppvBits := 0
hbm := DllCall("CreateDIBSection", "Ptr", hdcMem, "Ptr", bi, "UInt", 0, "Ptr*", &ppvBits, "Ptr", 0, "UInt", 0, "Ptr")
DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")

; GDI+ Graphics handle
pGraphics := 0
DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdcMem, "Ptr*", &pGraphics)
DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)     ; AntiAlias
DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", pGraphics, "Int", 4) ; AntiAliasGridFit

; Horizontal Linear Gradient Brush (0 -> Width)
pt1 := Buffer(8, 0)
pt2 := Buffer(8, 0)
NumPut("Float", 0.0, pt1, 0)
NumPut("Float", 0.0, pt1, 4)
NumPut("Float", Float(Width), pt2, 0)
NumPut("Float", 0.0, pt2, 4)

pGradBrush := 0
DllCall("gdiplus\GdipCreateLineBrush", "Ptr", pt1, "Ptr", pt2, "UInt", 0, "UInt", 0, "Int", 0, "Ptr*", &pGradBrush)

; 4-Stop Opacity Gradation:
; 0.0 -> Alpha 0 (transparent left wing)
; FadeRatio -> MaxOpacity (smooth fade in)
; 1.0 - FadeRatio -> MaxOpacity (solid center)
; 1.0 -> Alpha 0 (smooth fade out to right wing)
centerARGB := (MaxOpacity << 24) | (BgR << 16) | (BgG << 8) | BgB
edgeARGB   := (0 << 24) | (BgR << 16) | (BgG << 8) | BgB

colors := Buffer(16, 0)
NumPut("UInt", edgeARGB, colors, 0)
NumPut("UInt", centerARGB, colors, 4)
NumPut("UInt", centerARGB, colors, 8)
NumPut("UInt", edgeARGB, colors, 12)

pos := Buffer(16, 0)
NumPut("Float", 0.0, pos, 0)
NumPut("Float", Float(FadeRatio), pos, 4)
NumPut("Float", Float(1.0 - FadeRatio), pos, 8)
NumPut("Float", 1.0, pos, 12)

DllCall("gdiplus\GdipSetLinePresetBlend", "Ptr", pGradBrush, "Ptr", colors, "Ptr", pos, "Int", 4)

; Text Font & Brush
pFamily := 0
DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", FontName, "Ptr", 0, "Ptr*", &pFamily)
pFont := 0
DllCall("gdiplus\GdipCreateFont", "Ptr", pFamily, "Float", FontSize, "Int", 1, "Int", 3, "Ptr*", &pFont) ; 1 = Bold, 3 = UnitPoint

textARGB := (255 << 24) | (TextR << 16) | (TextG << 8) | TextB
pTextBrush := 0
DllCall("gdiplus\GdipCreateSolidFill", "UInt", textARGB, "Ptr*", &pTextBrush)

; String Alignment
pFormat := 0
DllCall("gdiplus\GdipCreateStringFormat", "Int", 0, "Int", 0, "Ptr*", &pFormat)
DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", pFormat, "Int", 1)     ; Center horizontal
DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", pFormat, "Int", 1) ; Center vertical

rectF := Buffer(16, 0)
NumPut("Float", 0.0, rectF, 0)
NumPut("Float", 0.0, rectF, 4)
NumPut("Float", Float(Width), rectF, 8)
NumPut("Float", Float(Height), rectF, 12)

; UpdateLayeredWindow parameters
ptSrc := Buffer(8, 0)
wndSize := Buffer(8, 0)
NumPut("Int", Width, wndSize, 0)
NumPut("Int", Height, wndSize, 4)

blend := Buffer(4, 0)
NumPut("UChar", 0, blend, 0)   ; AC_SRC_OVER
NumPut("UChar", 0, blend, 1)   ; AC_SRC_ALPHA
NumPut("UChar", 255, blend, 2) ; SourceConstantAlpha
NumPut("UChar", 1, blend, 3)   ; AC_SRC_ALPHA (use per-pixel alpha)

; Show initial window position
ClockGui.Show("x" . NormalX . " y" . NormalY . " w" . Width . " h" . Height . " NoActivate")

; Redraw & Clock Update
LastTimeStr := ""

DrawClock(timeString) {
    global LastTimeStr
    if (timeString == LastTimeStr)
        return
    LastTimeStr := timeString

    ; Clear surface to fully transparent
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", pGraphics, "UInt", 0)

    ; Draw opacity gradation background
    DllCall("gdiplus\GdipFillRectangle", "Ptr", pGraphics, "Ptr", pGradBrush, "Float", 0, "Float", 0, "Float", Width, "Float", Height)

    ; Draw centered time text
    DllCall("gdiplus\GdipDrawString", "Ptr", pGraphics, "WStr", timeString, "Int", -1, "Ptr", pFont, "Ptr", rectF, "Ptr", pFormat, "Ptr", pTextBrush)

    ; Blit to layered window
    DllCall("UpdateLayeredWindow", "Ptr", ClockGui.Hwnd, "Ptr", 0, "Ptr", 0, "Ptr", wndSize, "Ptr", hdcMem, "Ptr", ptSrc, "UInt", 0, "Ptr", blend, "UInt", 2)
}

UpdateClock() {
    DrawClock(FormatTime(, TimeFormat))
}

; Initial render
UpdateClock()

; --- TIMERS ---
SetTimer(UpdateClock, 1000)

if (EnableDodge || EnableHotCorners)
    SetTimer(CheckMouseAndCorners, 100)

; --- LEOPARDWM HELPERS & COLCTRL GUI ---
global colctrl := ""
global colctrlVisible := false

LwmCmd(args) {
    static lwmPath := ""
    if (lwmPath == "") {
        if FileExist("C:\Program Files\LeopardWM\bin\lwm.exe")
            lwmPath := '"C:\Program Files\LeopardWM\bin\lwm.exe"'
        else
            lwmPath := "lwm"
    }
    try Run(lwmPath . " " . args,, "Hide")
}

GetLeopardWidthPresets() {
    configPath := A_AppData . "\leopardwm\config\config.toml"
    presets := [0.5, 0.69, 0.92] ; Default fallback presets
    if FileExist(configPath) {
        try {
            content := FileRead(configPath)
            if RegExMatch(content, "s)\[layout\][\s\S]*?width_presets\s*=\s*\[(.*?)\]", &m) {
                found := []
                pos := 1
                while RegExMatch(m[1], "([0-9]*\.?[0-9]+)", &numMatch, pos) {
                    val := Float(numMatch[1])
                    if (val > 0.05 && val <= 1.0)
                        found.Push(val)
                    pos := numMatch.Pos + numMatch.Len
                }
                if (found.Length >= 1)
                    presets := found
            }
        }
    }
    return presets
}

InitColCtrl() {
    global colctrl, colctrlVisible
    presets := GetLeopardWidthPresets()

    colctrl := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "colctrl")
    colctrl.BackColor := "14141E"
    colctrl.MarginX := 12
    colctrl.MarginY := 12

    colctrl.SetFont("s10 Bold cFFFFFF", "Segoe UI")
    colctrl.Add("Text", "w140 Center", "Column Width")

    colctrl.SetFont("s9 Norm cDCDCDC", "Segoe UI")

    ; Add 3 width preset buttons
    limit := Min(3, presets.Length)
    Loop limit {
        idx := A_Index
        p := presets[idx]
        pct := Round(p * 100)
        btn := colctrl.Add("Button", "w140 h30 y+8", pct . "%  (" . p . ")")
        btn.OnEvent("Click", ((val, *) => ApplyWidth(val)).Bind(p))
    }

    ; Add Fullscreen button
    fsBtn := colctrl.Add("Button", "w140 h30 y+8", "⛶ Fullscreen")
    fsBtn.OnEvent("Click", (*) => ApplyFullscreen())

    colctrl.OnEvent("Escape", (*) => CloseColCtrl())
}

ApplyWidth(fraction) {
    CloseColCtrl()
    LwmCmd("set-width --fraction " . fraction)
}

ApplyFullscreen() {
    CloseColCtrl()
    LwmCmd("toggle-fullscreen")
}

ShowColCtrl() {
    global colctrl, colctrlVisible
    if (colctrlVisible)
        return

    ; Recreate to ensure fresh config presets if config.toml was modified
    if (colctrl) {
        try colctrl.Destroy()
        colctrl := ""
    }

    InitColCtrl()
    colctrl.Show("x15 y15 AutoSize")
    colctrlVisible := true
}

CloseColCtrl() {
    global colctrl, colctrlVisible
    if (colctrl && colctrlVisible) {
        colctrl.Hide()
        colctrlVisible := false
    }
}

; Close colctrl when window loses activation (e.g. click outside)
OnMessage(0x0006, OnWindowActivate) ; WM_ACTIVATE
OnWindowActivate(wParam, lParam, msg, hwnd) {
    global colctrl, colctrlVisible
    if (colctrl && hwnd == colctrl.Hwnd && (wParam & 0xFFFF) == 0) {
        CloseColCtrl()
    }
}

; --- MOUSE HOVER & HOT CORNERS LOGIC ---
IsDodged := false
EdgeHoverCount := 0
screenWidth := A_ScreenWidth
bottomEdge := A_ScreenHeight - 1

CheckMouseAndCorners() {
    global IsDodged, EdgeHoverCount

    CoordMode("Mouse", "Screen")
    MouseGetPos(&x, &y)

    ; 1. Clock Dodge Logic
    if (EnableDodge) {
        ; Includes 15px buffer around the clock's resting position
        isNearClock := (x >= NormalX - 15 && x <= NormalX + Width + 15 && y >= 0 && y <= Height + 15)

        if (isNearClock && !IsDodged) {
            ClockGui.Move(DodgeX, NormalY)
            IsDodged := true
        } else if (!isNearClock && IsDodged) {
            ClockGui.Move(NormalX, NormalY)
            IsDodged := false
        }
    }

    ; 2. Hot Corners / Edges
    if (!EnableHotCorners)
        return

    static inTopLeft     := false
    static inTopRight    := false
    static inBottomLeft  := false
    static inBottomRight := false

    isTopLeft     := (x <= 1 && y <= 1)
    isTopRight    := (x >= screenWidth - 2 && y <= 1)
    isBottomLeft  := (x <= 1 && y >= bottomEdge - 1)
    isBottomRight := (x >= screenWidth - 2 && y >= bottomEdge - 1)
    isBottomEdge  := (y >= bottomEdge && x > 30 && x < screenWidth - 30)

    ; Top-Left Corner: show colctrl GUI with 3 width presets + fullscreen
    if (isTopLeft) {
        if (!inTopLeft) {
            inTopLeft := true
            ShowColCtrl()
        }
    } else if (x > 20 || y > 20) {
        inTopLeft := false
    }

    ; Top-Right Corner: centering active/focused column/window
    if (isTopRight) {
        if (!inTopRight) {
            inTopRight := true
            LwmCmd("center-column")
        }
    } else if (x < screenWidth - 20 || y > 20) {
        inTopRight := false
    }

    ; Bottom-Left Corner: switch focus to left column
    if (isBottomLeft) {
        if (!inBottomLeft) {
            inBottomLeft := true
            LwmCmd("focus left")
        }
    } else if (x > 20 || y < bottomEdge - 20) {
        inBottomLeft := false
    }

    ; Bottom-Right Corner: switch focus to right column
    if (isBottomRight) {
        if (!inBottomRight) {
            inBottomRight := true
            LwmCmd("focus right")
        }
    } else if (x < screenWidth - 20 || y < bottomEdge - 20) {
        inBottomRight := false
    }

    ; Bottom Edge: Show Taskbar (when not in bottom corners)
    if (isBottomEdge) {
        if WinExist("ahk_class Shell_TrayWnd") {
            WinSetAlwaysOnTop(1, "ahk_class Shell_TrayWnd")
            WinShow("ahk_class Shell_TrayWnd")
            WinActivate("ahk_class Shell_TrayWnd")
        }
        EdgeHoverCount := -1
    }
}

; --- CLEANUP ON EXIT ---
OnExit(CleanupGDI)

CleanupGDI(*) {
    ; Stop timers first to prevent drawing during teardown
    SetTimer(UpdateClock, 0)
    if (EnableDodge || EnableHotCorners)
        SetTimer(CheckMouseAndCorners, 0)

    global colctrl
    if colctrl {
        try colctrl.Destroy()
        colctrl := ""
    }

    try {
        ; 1. Delete GDI+ drawing objects (brushes, font, format) first
        if pGradBrush
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pGradBrush)
        if pTextBrush
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pTextBrush)
        if pFont
            DllCall("gdiplus\GdipDeleteFont", "Ptr", pFont)
        if pFamily
            DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", pFamily)
        if pFormat
            DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", pFormat)

        ; 2. Delete GDI+ Graphics (releases its hold on the HDC)
        if pGraphics
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)

        ; 3. Shut down GDI+ while the token is still valid and the DLL is loaded
        if gdiToken
            DllCall("gdiplus\GdiplusShutdown", "Ptr", gdiToken)

        ; 4. Now free the GDI objects (DC, bitmap) — safe after GDI+ is fully shut down
        if hbm
            DllCall("DeleteObject", "Ptr", hbm)
        if hdcMem
            DllCall("DeleteDC", "Ptr", hdcMem)
    }
}

; --- CLOSE COLCTRL ON CLICK OUTSIDE ---
#HotIf (colctrlVisible && WinExist("ahk_id " . (colctrl ? colctrl.Hwnd : 0)))
~*LButton::
~*RButton:: {
    if (!colctrlVisible)
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(,, &clickedHwnd)
    if (clickedHwnd != colctrl.Hwnd) {
        parentHwnd := DllCall("GetAncestor", "Ptr", clickedHwnd, "UInt", 2, "Ptr") ; GA_ROOT
        if (parentHwnd != colctrl.Hwnd) {
            CloseColCtrl()
        }
    }
}
#HotIf
