CPU 1
org $506
.start
.main
	lda #0:ldx #$ff:jsr osbyte		; 0: query machine type
	; anywhere from 3 to 5 is OK
	cpx #3:bcc type_not_ok                          ; Master 128
	beq hint
	; for Master 128s give specific advice for what to do if no swram
	stz lk_hint
.hint
	cpx #6:bcc type_ok                              ; Master Compact
.type_not_ok
	brk:equs 0,"BBC Master required!",0
.type_ok
	lda #68:jsr osbyte_zerox
	txa:ora #&f0:inc a:beq swram_ok
.noswram brk:equs 0,"Need sideways RAM in banks 4-7."
.lk_hint equs 13,10,"(Set LK18 and LK19 west?)",0
.swram_ok
	sec: ror $ff:lda #126:jsr osbyte
	lda #234:jsr osbyte_zerox ;234
	lda #108:ldx #1:jsr osbyte		; 108: page in shadow RAM
	lda #22:jsr &FFCB:lda #135:jsr &FFCB
	lda #8:sta $fe00:lda #%11110011:sta $fe01
	;; tape on
	LDA #&85:STA &FE10
	LDA #&D5:STA &FE08
.sync
 	ldy #2
.syncloop
 	jsr get_crunched_byte
 	cmp #$f7
 	bne sync
 	dey
 	bpl syncloop
.loadinitial
	jsr get_crunched_byte
	sta $400,Y
	dey
	bne loadinitial
	jsr decrunch
	;lda #8:sta $fe00
	:lda #%11010011:sta $fe01
	lda #108:jsr osbyte_zerox       ; 108: page in main RAM
	jsr decrunch
	jmp &0900
.get_crunched_byte
	PHP
.no
 	LDA &FE08
	LSR A
	BCC no
	LDA &FE09
	PLP
	RTS
.osbyte_zerox
	ldx #0
.osbyte
	jmp ($20A)
	
;.tabl_bit
;        equb %11100001, %10001100, %11100010
.end
include "exodecr.s"
save "boottape",$500,end
;include "irqloader.asm"
