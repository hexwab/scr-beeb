;******************************************************************
; 6502 BBC Micro Compressed VGM (VGC) Music Player
; By Simon Morris
; https://github.com/simondotm/vgm-packer
;******************************************************************

;---------------------------------------------------------------
; VGM Player Library code
;---------------------------------------------------------------

.vgm_start

; none of the following have to be zp for indirect addressing reasons.
.zp_literal_cnt skip 2    ; literal count LO/HI, 7 references
.zp_match_cnt   skip 2    ; match count LO/HI, 10 references
; temporary vars
.zp_temp        skip 2 ; 2 bytes ; used only by lz_decode_byte and lz_fetch_count, does not need to be zp apart from memory/speed reasons

; The following vars only apply if Huffman support is enabled
IF ENABLE_HUFFMAN

; we re-use the LZ read ptr, since the huffman routine replaces the lz_fetch_byte
huff_readptr    = zp_stream_src 

.HUFF_ZP SKIP 11 ;= zp_temp + 2

; huffman decoder stream context - CHECK:needs to be in ZP? prefix with zp if so
zp_huff_bitbuffer  = HUFF_ZP + 0    ; huffman decoder bit buffer - 1 byte, referenced by inner loop
zp_huff_bitsleft   = HUFF_ZP + 1    ; huffman decoder bit buffer size - 1 byte, referenced by inner loop

; these variables are only used during a byte fetch - ie. not stream specific.
; ZP only for byte & cycle speed. Could be absolute memory.
huff_code       = HUFF_ZP + 2 ; 2
huff_firstcode  = HUFF_ZP + 4 ; 2
huff_startindex = HUFF_ZP + 6 ; 1
huff_codesize   = HUFF_ZP + 7 ; 1
huff_index      = HUFF_ZP + 8 ; 2
huff_numcodes   = HUFF_ZP + 10 ; 1

ENDIF ; ENABLE_HUFFMAN


; when mounting a VGM file we use these four variables as temporaries
; they are not speed or memory critical.
; they may need to be zero page due to indirect addressing
zp_block_data = zp_stream_src ; re-uses zp_stream_src, must be zp ; zp_buffer+0 ; must be zp
zp_block_size = zp_temp+0 ; does not need to be zp



;--------------------------------------------------
; user callable routines:
;  vgm_init()
;  vgm_update()
;  sn_reset()
;  sn_write()
;--------------------------------------------------

; Sound chip data from the vgm player
IF 1;ENABLE_VGM_FX
.vgm_fx SKIP 11
; first 8 bytes are:
; tone0 LO, tone1 LO, tone2 LO, tone3, vol0, vol1, vol2, vol3 (all 4-bit values)
; next 3 bytes are:
; tone0 HI, tone1 HI, tone2 HI (all 6-bit values)
VGM_FX_TONE0_LO = vgm_fx+0
VGM_FX_TONE1_LO = vgm_fx+1
VGM_FX_TONE2_LO = vgm_fx+2
VGM_FX_TONE3_LO = vgm_fx+3 ; noise
VGM_FX_VOL0     = vgm_fx+4
VGM_FX_VOL1     = vgm_fx+5
VGM_FX_VOL2     = vgm_fx+6
VGM_FX_VOL3     = vgm_fx+7 ; noise
VGM_FX_TONE0_HI = vgm_fx+8
VGM_FX_TONE1_HI = vgm_fx+9
VGM_FX_TONE2_HI = vgm_fx+10

ENDIF

;-------------------------------------------
; vgm_update
;-------------------------------------------
;  call every 50Hz to play music
;  vgm_init must be called prior to this
; On entry A is non-zero if the music should be looped
;  returns non-zero when VGM is finished.
;-------------------------------------------
.vgm_update
{
    lda vgm_finished
    bne exit

    ; SN76489 data register format is %1cctdddd where cc=channel, t=0=tone, t=1=volume, dddd=data
    ; The data is run length encoded.
    ; Get Channel 3 tone first because that contains the EOF marker

    ; Update Tone3
    lda#3:jsr vgm_update_register1  ; on exit C set if data changed, A is last value
    bcc no_tone3
    cmp #&e8       ; EOF marker? (0x08 is an invalid tone 3 value)
    beq finished
    cmp #$ef       ; check if it's a tone3 skip command (&ef) before we play it
    beq no_tone3 ; - this prevents the LFSR being reset unnecessarily
    sta VGM_FX_TONE3_LO
    jsr sn_write_real
.no_tone3
    lda#7:jsr vgm_update_register1  ; Volume3
    bcc no_vol3
    sta VGM_FX_VOL3
    jsr sn_write_with_attenuation
.no_vol3
    lda#0:jsr vgm_update_register2  ; Tone0
    bcc no_tone0
    jsr do_tone0
    ;jsr do_normal_tone
.no_tone0
    lda#1:jsr vgm_update_register2  ; Tone1
    bcc no_tone1
    jsr do_tone1
    ;jsr do_normal_tone
.no_tone1
    lda#2:jsr vgm_update_register2  ; Tone2
    bcc no_tone2
    jsr do_tone2
    ;jsr do_normal_tone
.no_tone2
    lda#4:jsr vgm_update_volume_register  ; Volume0
    bcc no_vol0
    sta u1writeval ;tone0_writeval
.no_vol0
    lda#5:jsr vgm_update_volume_register  ; Volume1
    bcc no_vol1
    sta u2writeval ;tone1_writeval
.no_vol1
    lda#6:jsr vgm_update_volume_register  ; Volume2
    bcc no_vol2
    sta s2writeval ;tone2_writeval
.no_vol2
    lda #0 ; X is no longer zero after sn_write
.exit
    rts

.finished
    ; end of tune reached
    \\ SCR ONLY HACK LOOP ADDRESS
    ldx #LO(vgm_data_loop);vgm_source+0
    ldy #HI(vgm_data_loop);vgm_source+1
    lda vgm_buffers
    jsr vgm_init
    bra vgm_update
}



;-------------------------------------------
; local vgm workspace
;-------------------------------------------

VGM_STREAM_CONTEXT_SIZE = 10 ; number of bytes total workspace for a stream
VGM_STREAMS = 8

;ALIGN 16 ; doesnt have to be aligned, just for debugging ease
.vgm_streams ; decoder contexts - 8 bytes per stream, 8 streams (64 bytes)
    skip  VGM_STREAMS*VGM_STREAM_CONTEXT_SIZE
    ; 0 zp_stream_src     ; stream data ptr LO/HI
    ; 2 zp_literal_cnt    ; literal count LO/HI
    ; 4 zp_match_cnt      ; match count LO/HI
    ; 6 lz_window_src     ; window read ptr - index
    ; 7 lz_window_dst     ; window write ptr - index
    ; 8 zp_huff_bitbuffer ; 1 byte, referenced by inner loop
    ; 9 huff_bitsleft     ; 1 byte, referenced by inner loop

.vgm_buffers  equb hi(vgm_stream_buffers)   ; the HI byte of the address where the buffers are stored
.vgm_finished equb 0    ; a flag to indicate player has reached the end of the vgm stream
.vgm_flags  equb 0      ; flags for current vgm file. bit7 set stream is huffman coded. bit 6 set if stream is 16-bit LZ4 offsets
.vgm_temp equb 0        ; used by vgm_update_register1()
.vgm_loop equb 0        ; non zero if tune is to be looped
.vgm_source equw vgm_data_intro  ; vgm data address
.firstbyte equb 0
.vgm_paused equb 0
; 8 counters for VGM register update counters (RLE)
.vgm_register_counts
    SKIP 8

; Table of SN76489 flags for the 8 LATCH/DATA registers
; %1cctdddd 
.vgm_register_headers
    EQUB &80 + (0<<5)   ; Tone 0
    EQUB &80 + (1<<5)   ; Tone 1
    EQUB &80 + (2<<5)   ; Tone 2
    EQUB &80 + (3<<5)   ; Tone 3
    EQUB &90 + (0<<5)   ; Volume 0
    EQUB &90 + (1<<5)   ; Volume 1
    EQUB &90 + (2<<5)   ; Volume 2
    EQUB &90 + (3<<5)   ; Volume 3

.bass_flag
    equb 0, 0, 0
	
; VGC file parsing - Skip to the next block. 
; on entry zp_block_data points to current block (header)
; on exit zp_block_data points to next block
; Clobbers Y
.vgm_next_block
{
    ; read 16-bit block size to zp_block_size
    ; +4 to compensate for block header
    ldy #0
    lda (zp_block_data),Y
    clc
    adc #4
    sta zp_block_size+0
    iny
    lda (zp_block_data),Y
    adc #0
    sta zp_block_size+1

    ; move to next block
    lda zp_block_data+0
    clc
    adc zp_block_size+0
    sta zp_block_data+0
    lda zp_block_data+1
    adc zp_block_size+1
    sta zp_block_data+1
    rts
}

; VGC file parsing - Initialise the system for the provided in-memory VGC data stream.
; On entry X/Y point to Lo/Hi address of the vgc data
.vgm_init
.vgm_stream_mount
{
    ; parse data stream
    ; VGC broadly uses LZ4 frame & block formats for convenience
    ; however there are assumptions for format:
    ;  Magic number[4], Flags[1], MaxBlockSize[1], Header checksum[1]
    ;  Contains 8 blocks
    ; Obviously since this is an 8-bit CPU no files or blocks can be > 64Kb in size

    ; VGC streams have a different magic number to LZ4
    ; [56 47 43 XX]
    ; where XX:
    ; bit 6 - LZ 8 bit (0) or 16 bit (1) [unsupported atm]
    ; bit 7 - Huffman (1) or no huffman (0)

    stx zp_block_data+0
    sty zp_block_data+1

    ; get the stream flags (huffman/8 or 16 bit offsets)
    ldy #3
    lda (zp_block_data), y
    sta vgm_flags

    ; Skip frame header, and move to first block
    lda zp_block_data+0
    clc
    adc #7
    sta zp_block_data+0
    bcc no_block_hi
    inc zp_block_data+1
.no_block_hi

IF ENABLE_HUFFMAN
    ; first block contains the bitlength and symbol tables
    bit vgm_flags
    bpl skip_hufftable

    ; stash table sizes for later
IF FALSE
    ; we dont need the symbol table size for anything.
    ; left here for future possibility of GD3 tags
    ldy #8
    lda (zp_block_data),Y   ; symbol table size
    sta zp_symbol_table_size    
    iny
ELSE
    ldy #9
ENDIF
    lda (zp_block_data),Y   ; bitlength table size
    sta stashLengthTableSize+1 ; **SELF MODIFYING**
    ; compensate for the first byte (range is 0-nbits inclusive), value always < 254
    inc stashLengthTableSize+1 ; **SELF-MODIFYING**

    ; store the address of the bitlengths table directly in the huff_fetch_byte routine
    lda zp_block_data + 0
    clc
    adc #4+4+1        ; skip lz blocksize, huff block size and symbol count byte
    sta LOAD_LENGTH_TABLE + 1   ; ** SELF MODIFICATION ***
    lda zp_block_data + 1
    adc #0
    sta LOAD_LENGTH_TABLE + 2   ; ** SELF MODIFICATION ***

    ; store the address of the symbols table directly in the huff_fetch_byte routine
    lda LOAD_LENGTH_TABLE + 1
    clc
.stashLengthTableSize
    adc #0 ; length table size **SELF MODIFIED - see above **
    sta LOAD_SYMBOL_TABLE + 1   ; ** SELF MODIFICATION ***
    lda LOAD_LENGTH_TABLE + 2
    adc #0
    sta LOAD_SYMBOL_TABLE + 2   ; ** SELF MODIFICATION ***

    ; skip to next block
    jsr vgm_next_block

.skip_hufftable
ENDIF ; ENABLE_HUFFMAN


    ; read the block headers (size)
    ldx #0
    ; clear vgm finished flag
    stx vgm_finished
.block_loop
 
    ; get start address of encoded data for vgm_stream[x] (block ptr+4)
    lda zp_block_data+0
    clc
    adc #4  ; skip block header
    sta vgm_streams + VGM_STREAMS*0, x  ; zp_stream_src LO
    lda zp_block_data+1
    adc #0
    sta vgm_streams + VGM_STREAMS*1, x  ; zp_stream_src HI

    ; init the rest
    lda #0
    sta vgm_streams + VGM_STREAMS*2, x  ; literal cnt 
    sta vgm_streams + VGM_STREAMS*3, x  ; literal cnt 
    sta vgm_streams + VGM_STREAMS*4, x  ; match cnt 
    sta vgm_streams + VGM_STREAMS*5, x  ; match cnt 
    sta vgm_streams + VGM_STREAMS*6, x  ; window src ptr 
    sta vgm_streams + VGM_STREAMS*7, x  ; window dst ptr 
    sta vgm_streams + VGM_STREAMS*8, x  ; huff bitbuffer
    sta vgm_streams + VGM_STREAMS*9, x  ; huff bitsleft

    ; setup RLE tables
    lda #1
    sta vgm_register_counts, X

    ; move to next block
    jsr vgm_next_block

    ; for all 8 blocks
    inx
    cpx #8
    bne block_loop

IF ENABLE_HUFFMAN
IF HUFFMAN_INLINE
    ; setup byte fetch routines to lz_fetch_byte or huff_fetch_byte
    ; depending if data file is huffman encoded or not
    ; default compilation is lz_fetch_byte, so this code is not needed if HUFFMAN disabled
    ldx #lo(lz_fetch_byte)
    ldy #hi(lz_fetch_byte)

    ; if bit7 of vgm_flags is set, its a huffman stream
    bit vgm_flags        ; [3 zp, 4 abs] (2)
    bpl no_huffman  ; [2, +1, +2] (2)
    
    ldx #lo(huff_fetch_byte)
    ldy #hi(huff_fetch_byte)
.no_huffman
    stx fetchByte1+1
    sty fetchByte1+2
    stx fetchByte2+1
    sty fetchByte2+2
    sty fetchByte3+2
    stx fetchByte3+1
IF LZ4_FORMAT
    stx fetchByte4+1
    sty fetchByte4+2
ENDIF
    stx fetchByte5+1
    sty fetchByte5+2
ENDIF ; HUFFMAN_INLINE
ENDIF ;ENABLE_HUFFMAN    

    rts
}

;----------------------------------------------------------------------
; fetch register data byte from register stream selected in A
; This byte will be LZ4 encoded
;  A is register id (0-7)
;  clobbers X,Y
.vgm_get_register_data
{
    ; set the LZ4 decoder stream workspace buffer (initialised by vgm_stream_mount)
    tax
    clc
    adc vgm_buffers ; hi byte of the base address of the 2Kb (8x256) vgm stream buffers
    ; store hi byte of where the 256 byte vgm stream buffer for this stream is located
    sta lz_window_src+1 ; **SELFMOD**
    sta lz_window_dst+1 ; **SELFMOD**

    ; calculate the stream buffer context
    stx loadX+1 ; Stash X for later *** SELF MODIFYING SEE BELOW ***

    ; since we have 8 separately compressed register streams
    ; we have to load the required decoder context to ZP
    lda vgm_streams + VGM_STREAMS*0, x
    sta zp_stream_src + 0
    lda vgm_streams + VGM_STREAMS*1, x
    sta zp_stream_src + 1

    lda vgm_streams + VGM_STREAMS*2, x
    sta zp_literal_cnt + 0
    lda vgm_streams + VGM_STREAMS*3, x
    sta zp_literal_cnt + 1

    lda vgm_streams + VGM_STREAMS*4, x
    sta zp_match_cnt + 0
    lda vgm_streams + VGM_STREAMS*5, x
    sta zp_match_cnt + 1

    lda vgm_streams + VGM_STREAMS*6, x
    sta lz_window_src   ; **SELF MODIFY** not ZP

    lda vgm_streams + VGM_STREAMS*7, x
    sta lz_window_dst   ; **SELF MODIFY** not ZP

IF ENABLE_HUFFMAN
    lda vgm_streams + VGM_STREAMS*8, x
    sta zp_huff_bitbuffer
    lda vgm_streams + VGM_STREAMS*9, x
    sta zp_huff_bitsleft
ENDIF

    ; then fetch a decompressed byte
    jsr lz_decode_byte
    sta loadA+1 ; Stash A for later - ** SMOD ** [4](2) faster than pha/pla 

    ; then we save the decoder context from ZP back to main ram
.loadX
    ldx #0  ; *** SELF MODIFIED - See above ***

    lda zp_stream_src + 0
    sta vgm_streams + VGM_STREAMS*0, x
    lda zp_stream_src + 1
    sta vgm_streams + VGM_STREAMS*1, x

    lda zp_literal_cnt + 0
    sta vgm_streams + VGM_STREAMS*2, x
    lda zp_literal_cnt + 1
    sta vgm_streams + VGM_STREAMS*3, x

    lda zp_match_cnt + 0
    sta vgm_streams + VGM_STREAMS*4, x
    lda zp_match_cnt + 1
    sta vgm_streams + VGM_STREAMS*5, x

    lda lz_window_src
    sta vgm_streams + VGM_STREAMS*6, x

    lda lz_window_dst
    sta vgm_streams + VGM_STREAMS*7, x

IF ENABLE_HUFFMAN
    lda zp_huff_bitbuffer
    sta vgm_streams + VGM_STREAMS*8, x
    lda zp_huff_bitsleft
    sta vgm_streams + VGM_STREAMS*9, x
ENDIF

.loadA
    lda #0 ;[2](2) - ***SELF MODIFIED - See above ***
    rts
}

; Fetch 1 register data byte from the encoded stream and send to sound chip (volumes & tone3)
; A is register to update
; on exit:
;    C is set if an update happened and Y contains last register value
;    C is clear if no updated happened and Y is preserved
;    X contains register provided in A on entry (0-7)

.vgm_update_register1
{
    clc
    tax
    dec vgm_register_counts,x ; no effect on C
    bne skip_register_update

    ; decode a byte & send to psg
    sta vgm_temp
    jsr vgm_get_register_data
    tay
    ; get run length (top 4-bits + 1)
    lsr a
    lsr a
    lsr a
    lsr a
    inc a
    ldx vgm_temp
    sta vgm_register_counts,x
    tya
    and #&0f
    ora vgm_register_headers,X
    sec
}
.skip_register_update
{
    rts
}

.vgm_update_volume_register
; same as vgm_update_register1 but does attenuation
; returns bitbang volume in A, C set if needed
{
	jsr vgm_update_register1
	bcc skip_register_update
	sta VGM_FX_VOL0-4,X
	bit bass_flag-4,X
	bmi do_bass_volume
	jsr sn_write_with_attenuation
	clc
	rts
.*do_bass_volume
	tax
	and #$f0
	sta remask+1
	txa
	and #$0f
	tax
	lda sn_volume_table,X
.remask ora #$00
	sec
	rts
}

; A is pitch register: $81, $a1, $c1
.set_bitbang_pitch
{
    jsr sn_write_real
    lda #$00
    jmp sn_write_real
}

; Fetch 2 register bytes (LATCH+DATA) from the encoded stream and send to sound chip (tone0, tone1, tone2)
; Same parameters as vgm_update_register1
.vgm_update_register2
{
    jsr vgm_update_register1    ; returns stream in X if updated, and C=0 if no update needed
    bcc skip_register_update
    sta firstbyte
    sta VGM_FX_TONE0_LO,X
    ; decode 2nd byte and return with it
    txa
    jsr vgm_get_register_data
    sta VGM_FX_TONE0_HI,X
    sec
    rts
}

; in: A has second byte. out: A has timer lo, Y has timer hi
.set_up_timer_values
{
    ; mask out bit 6 of data byte
    and #$3f
    tay
    lda firstbyte
    asl a
    asl a
    asl a
    asl a
    ora #$06
}
.alreadyon
{
    rts
}

;in: A has second byte
.do_tone0
{
    cmp #$40 ; bit 7 is always clear
    bcs do_bass
    ; bass is now off. was it previously on?
    bit bass_flag+0
    bpl do_normal_tone
    ; turn off IRQ, reset flag
    pha
    lda #$40
    sta $fe6e
    sta $fe6d ; clear
    stz bass_flag+0
    lda VGM_FX_VOL0 ; restore vol
    jsr sn_write_with_attenuation
    pla
    bra do_normal_tone
.do_bass
    jsr set_up_timer_values
    sta $fe66 ; tone0_bass_timer_lo
    sty $fe67 ; tone0_bass_timer_hi
    ; is bass already on?
    bit bass_flag+0
    bmi alreadyon
    ; enable timer
    lda #$c0 ; uservia_timer1
    sta $fe6e
    sta bass_flag+0 ; has top bit set
    lda #$81 ; set period to 1
    jmp set_bitbang_pitch
}

; in: A has second byte
.do_normal_tone
{
    tay
    lda firstbyte
    jsr sn_write_real
    tya
    jmp sn_write_real
}

;in: A has second byte
.do_tone1
{
    cmp #$40 ; bit 7 is always clear
    bcs do_bass
    ; bass is now off. was it previously on?
    bit bass_flag+1
    bpl do_normal_tone
    ; turn off IRQ, reset flag
    pha
    lda #$20
    sta $fe6e
    lda $fe68 ; clear
    stz bass_flag+1
    lda VGM_FX_VOL1 ; restore vol
    jsr sn_write_with_attenuation
    pla
    bra do_normal_tone
.do_bass
    jsr set_up_timer_values
    sta u2latchlo ; tone1_bass_timer_lo
    sty u2latchhi ; tone1_bass_timer_hi
    ; is bass already on?
    bit bass_flag+1
    bmi alreadyon
    ; enable timer
    sta $fe68 ; tone1_bass_timer_lo
    sty $fe69 ; tone1_bass_timer_hi
    lda #$a0 ; uservia_timer2
    sta $fe6e
    sta $fe6d ; force IRQ
    sta bass_flag+1 ; has top bit set
    lda #$a1 ; set period to 1
    jmp set_bitbang_pitch
.alreadyon
    rts
}

;in: A has second byte
.do_tone2
{
    cmp #$40 ; bit 7 is always clear
    bcs do_bass
    ; bass is now off. was it previously on?
    bit bass_flag+2
    bpl do_normal_tone
    ; turn off IRQ, reset flag
    pha
    lda #$20
    sta $fe4e
    lda $fe48 ; clear
    stz bass_flag+2
    lda VGM_FX_VOL2 ; restore vol
    jsr sn_write_with_attenuation
    pla
    bra do_normal_tone
.do_bass
    jsr set_up_timer_values
    sta s2latchlo ; tone2_bass_timer_lo
    sty s2latchhi ; tone2_bass_timer_hi
    ; is bass already on?
    bit bass_flag+2
    bmi alreadyon
    ; enable timer
    sta $fe48 ; tone1_bass_timer_lo
    sty $fe49 ; tone1_bass_timer_hi
    lda #$a0 ; sysvia_timer2
    sta $fe4e
    sta $fe4d ; force IRQ
    sta bass_flag+2 ; has top bit set
    lda #$c1 ; set period to 1
    jmp set_bitbang_pitch
.alreadyon
    rts
}

.vgm_pause
{
	lda #$60
	sta $fe6e ;uservia timer1,2 off
	lda #$20
	sta $fe4e ;sysvia timer2 off
	sec
	ror vgm_paused
}
.sn_reset
{
	\\ Zero volume on all channels
	lda #&9f : jsr sn_write_real
	lda #&bf : jsr sn_write_real
	lda #&df : jsr sn_write_real
	lda #&ff : jmp sn_write_real
}

; this is all terrible
.vgm_unpause
{
	bit vgm_paused
	bmi restore
	rts
.restore
	php
	sei
	stz vgm_paused
	stz bass_flag+0
	stz bass_flag+1
	stz bass_flag+2

	lda VGM_FX_TONE0_HI
	sta firstbyte
	lda VGM_FX_TONE0_LO
	jsr do_tone0
	lda VGM_FX_TONE1_HI
	sta firstbyte
	lda VGM_FX_TONE1_LO
	jsr do_tone1
	lda VGM_FX_TONE2_HI
	sta firstbyte
	lda VGM_FX_TONE2_LO
	jsr do_tone2
	ldx #6
.loop
	lda ptrlo-4,X
	sta wr+1
	lda ptrhi-4,X
	sta wr+2
	lda vgm_fx,X
	phx
	jsr vgm_update_volume_register+5
	bcc skip
.wr	sta $eeee
.skip
	plx
	dex
	cpx #3
	bne loop
	lda VGM_FX_VOL3
	jsr sn_write_with_attenuation
	lda VGM_FX_TONE3_LO
	plp
	jmp sn_write_real
.ptrlo	equb LO(u1writeval), LO(u2writeval), LO(s2writeval)
.ptrhi	equb HI(u1writeval), HI(u2writeval), HI(s2writeval)
}


.vgm_end


; fetch a byte from the currently selected compressed register data stream
; either huffman encoded or plain data
; returns byte in A, clobbers Y
.lz_fetch_byte
{
IF ENABLE_HUFFMAN == TRUE
IF HUFFMAN_INLINE == FALSE
    ; if bit7 of vgm_flags is set, its a huffman stream
    bit vgm_flags        ; [3 zp, 4 abs] (2)
    bmi huff_fetch_byte  ; [2, +1, +2] (2) see below
ENDIF ; HUFFMAN_INLINE
ENDIF ; ENABLE_HUFFMAN

    ; otherwise plain LZ4 byte fetch
    ldy #0
    lda (zp_stream_src),y
    inc zp_stream_src+0
    bne ok
    inc zp_stream_src+1
.ok
    rts
}



IF ENABLE_HUFFMAN

;-------------------------------
; huffman decoder routines
;-------------------------------

; TODO: Optimize with a peek buffer.
; 70-90% of codes are 7 bits or less. At 8 bits the % is higher.
; Peek buffer translates to two lookups and no loops.
; http://cbloomrants.blogspot.com/2010/08/08-11-10-huffman-arithmetic-equivalence.html
; 7 bits peek would require 2x 128 byte tables (256 bytes total extra to data stream).

; this routine must be located within branch reach of lz_fetch_byte()
.huff_fetch_byte
{
    ; code = codesize = firstcode = startindex = 0
    lda #0
    sta huff_code + 0
    sta huff_code + 1
    sta huff_codesize
    sta huff_firstcode + 0
    sta huff_firstcode + 1
    sta huff_startindex

    ; skip over nextbit on first entry - this layout saves a jmp per bitlength
    jmp decode_loop
}
.nextbit
{
    ; otherwise, move to the next bit length
    ; firstcode += numcodes
    lda huff_firstcode + 0
    clc
    adc huff_numcodes
    sta huff_firstcode + 0
    lda huff_firstcode + 1
    adc #0
    sta huff_firstcode + 1

    ; firstcode <<= 1
    asl huff_firstcode + 0
    rol huff_firstcode + 1
    
    ; startindex += numcodes
    lda huff_startindex
    clc
    adc huff_numcodes
    sta huff_startindex
    
    ; keep going until we find a symbol
    ; falls into decode_loop
}
.decode_loop
{
    ; check if we need to refill bitbuffer
    lda zp_huff_bitsleft
    bne got_bits
    ; fetch 8 more bits
    ldy #0
    lda (huff_readptr), y
    sta zp_huff_bitbuffer
    lda #8
    sta zp_huff_bitsleft
    inc huff_readptr + 0
    bne got_bits
    inc huff_readptr + 1
.got_bits

    ; build code

    ; bitsleft -=1
    dec zp_huff_bitsleft
    ; bit = (bitbuffer & 128) >> 7
    ; buffbuffer <<= 1
    asl zp_huff_bitbuffer           ; bit7 -> C
    ; code = (code << 1) | bit
    rol huff_code + 0       ; C -> bit0, bit7 -> C
    rol huff_code + 1       ; C -> bit8, bit15 -> C
    ; codesize += 1
    inc huff_codesize

    ; how many canonical codes have this many bits?
    ; numCodes = length_table[codesize]
    ldy huff_codesize
}
.LOAD_LENGTH_TABLE
{
    lda &FFFF, Y     ; ** MODIFIED ** See vgm_stream_mount
    sta huff_numcodes

    ; if input code so far is within the range of the first code with the current number of bits, it's a match
    ; index = code - firstcode
    sec
    lda huff_code + 0
    sbc huff_firstcode + 0
    sta huff_index + 0
    lda huff_code + 1
    sbc huff_firstcode + 1
    sta huff_index + 1

    ; if index < numcodes:
    ; if hi byte is non zero, is definitely > numcodes
    ; or numcodes >= index
    bne nextbit 

    ; we found our code, determine which symbol index it has.
    lda huff_index
    cmp huff_numcodes
    bcs nextbit
    
    ; code = startindex + index
    lda huff_startindex
    clc
    adc huff_index
    tay
}
.LOAD_SYMBOL_TABLE
{
    ; return symbol_table[code]
    lda &FFFF, Y     ; ** MODIFIED ** See vgm_stream_mount
    rts
}


ENDIF ; ENABLE_HUFFMAN




PRINT "    decoder code size is", (decoder_end-decoder_start), "bytes"
PRINT " vgm player code size is", (vgm_end-vgm_start), "bytes"
PRINT "total vgm player size is", (decoder_end-decoder_start) + (vgm_end-vgm_start), "bytes"
PRINT "      vgm buffer size is", (vgm_buffer_end-vgm_buffer_start), "bytes"


