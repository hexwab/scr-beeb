	cpu 1
	org $510
	INITSTACK = $c0
.start
.partno
	equb $FF
.irqdecr_init
{
	sei
	lda $0204
	sta oldirq+1
	lda $0205
	sta oldirq+2
	lda #<get_crunched_byte_irq
	sta $204
	lda #>get_crunched_byte_irq
	sta $205
	tsx
	stx stack1
	ldx $f4
	stx bank1
	ldx #INITSTACK
	txs
	;LDA #&85:STA &FE10
        ;LDA #&D5:STA &FE08	; tape on
	ldx #0
.loop
	lda banks,X
	sta decrunch_bank
	phx
	jsr decrunch
	plx
	inx
	stx partno
	cpx #banks_end-banks
	bne loop

	LDA #$45:STA &FE10 	; tape off
	lda oldirq+1
	sta $0204
	lda oldirq+2
	sta $0205
	bra notfirst
	
.stack1				;main stack
	equb 0
.stack2				;decrunch stack
	equb 0
.bank1
	equb 0
.decrunch_bank
	equb 7

BEEB_KERNEL_SLOT = 4
BEEB_CART_SLOT = 5
BEEB_GRAPHICS_SLOT = 6
BEEB_MUSIC_SLOT = 7

.banks
	equb BEEB_GRAPHICS_SLOT	;gfxearly
	equb BEEB_GRAPHICS_SLOT	;core
	equb BEEB_KERNEL_SLOT	;kernel
	equb BEEB_CART_SLOT	;cart
	equb BEEB_MUSIC_SLOT	;music
	equb BEEB_GRAPHICS_SLOT	;gfxlate
	equb BEEB_MUSIC_SLOT	;hazel
	equb BEEB_MUSIC_SLOT	;data
.banks_end

.get_crunched_byte_irq
	lda $fe08
	lsr a
	bcs yes
.oldirq
	jmp $ffff
.yes
	dec timer
	bne noover
	lda #120
	sta timer
	dec timeleft
	bpl noover
	lda #9
	sta timeleft
	dec timeleft+1
	bpl noover
	lda #5
	sta timeleft+1
	dec timeleft+2
.noover
	phx
	phy
	jsr tick_cb
	tsx
	stx stack1
	ldx $f4
	stx bank1
	ldx stack2
	txs
	ldx decrunch_bank
	stx $f4
	stx $fe30
	lda $fe09
	plx
	ply
	plp
	rts	; to decrunch
.first
	equb 0
.notfirst
	tsx
	stx stack2
	ldx stack1
	txs
	ldx bank1
	stx $f4
	stx $fe30
	ply
	plx
	bra oldirq
.timer
	equb 120
.timeleft
	equb 0,2,8
.tick_cb
	rts

	org $5d3
.*get_crunched_byte
	ASSERT get_crunched_byte = $5d3
	php
	phy
	phx
	bit first
	bmi notfirst
	sec
	ror first
	tsx
	stx stack2
	ldx stack1
	txs
	ldx bank1
	stx $f4
	stx $fe30
	cli
	rts 			; to main
}
IF 0
	;; trivial decrunch for testing
	out = $2000
.decrunch
{
	ldy #0
.loop
	jsr get_crunched_byte
	sta out,Y
	iny
	bne loop
	rts
}
ENDIF
.end
SAVE "irqdecr",start,end
INCLUDE "exodecr.s"
