CPU 1
org $500
.start	
.basic
	equb 13,0,0,$07,$d6,$b8,$50,13,255
.reloc	
	sec
	ror $ff
	lda #126
	jsr $fff4
	ldy #0
	sty $b9
	tsx
	lda $100,X
	sta $ba
.relocloop
	lda ($b9),Y
	sta start,Y
	iny
	bne relocloop
	jmp main
.main
	ldx #$ff:jsr next_osbyte		; 0: query machine type
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
	jsr osbyte_zerox;68
	txa:ora #&f0:inc a:beq swram_ok
.noswram brk:equs 0,"Need sideways RAM in banks 4-7."
.lk_hint equs 13,10,"(Set LK18 and LK19 west?)"
.osbytes
        equb 0,68,234,108,108
.swram_ok
	jsr osbyte_zerox ;234
	ldx #1:jsr next_osbyte		; 108: page in shadow RAM
	lda #22:jsr &FFCB:lda #130:jsr &FFCB
	lda #10
        sta $fe00
        sta $fe01
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
	jsr osbyte_zerox       ; 108: page in main RAM
	jsr decrunch
	jmp &4E00
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
.next_osbyte
	lda osbytes
	inc next_osbyte+1
	jmp ($20A)
	
;.tabl_bit
;        equb %11100001, %10001100, %11100010
.end
save "boottape",start,end
include "exodecr.s"
	
