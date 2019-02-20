; *****************************************************************************
; STUNT CAR RACER DISC
; *****************************************************************************

PUTFILE "build/Core", "Core", &E00, 0
PUTFILE "build/Loader2", "Loader2", &3F00, &3F00
PUTFILE "build/Data", "Data", &6000, 0
PUTFILE "build/Cart", "Cart", &8000, 0
PUTFILE "build/Beebgfx", "Beebgfx", &8000, 0
PUTFILE "build/Beebmus", "Beebmus", &8800, 0
PUTFILE "build/Hazel", "Hazel", &CB00, 0
PUTFILE "build/Kernel", "Kernel", &8000, 0
PUTFILE "build/scr-beeb-title-screen.dat", "Title", &3000, 0
PUTFILE "build/Loader", "Loader", &1900, &1900

; *****************************************************************************
; Additional files for the disk...
; *****************************************************************************

IF 1;_DEBUG     \\ grumble
PUTFILE "data/Hall.bin", "HALL", &0
PUTFILE "data/KCSave.bin", "KCSAVE", &0
PUTFILE "data/MPSave.bin", "MPSAVE", &0
ENDIF

PUTFILE "doc/readme.txt", "Readme", &0
PUTFILE "doc/Guide.txt", "Guide", &0
