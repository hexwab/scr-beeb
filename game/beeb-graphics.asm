.beeb_graphics_start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

include "build/flames-tables.asm"

.menu_header_graphic_begin
incbin "build/scr-beeb-header.dat"
skip 2560						; book space for the Mode 1 version...
.menu_header_graphic_end

include "build/wheels-tables.asm"

include "build/hud-font-tables.asm"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

._graphics_erase_flames
{
clc
lda ZP_12
adc #HI(flames_initial_erase_addr)
sta erase_write+2

ldy #LO(flames_initial_erase_addr)
ldx #0

.erase_loop

.erase_read:lda flames_erase_values,x
.erase_write:sta $ff00,y

tya
adc flames_erase_deltas,x
tay
bcc erase_noc
inc erase_write+2
clc
.erase_noc

inx

cpx #flames_erase_writes_size
bne erase_loop

rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

._graphics_draw_flames
{
asl A:tax

lda unmasked_tables+0,x:sta unmasked_read+1
lda unmasked_tables+1,x:sta unmasked_read+2

lda masked_masks_tables+0,x:sta masked_mask+1
lda masked_masks_tables+1,x:sta masked_mask+2

lda masked_values_tables+0,x:sta masked_value+1
lda masked_values_tables+1,x:sta masked_value+2

; unmasked

clc
lda ZP_12
adc #HI(flames_initial_unmasked_write_addr)
sta unmasked_write+2

ldy #LO(flames_initial_unmasked_write_addr)
ldx #0

.unmasked_loop

.unmasked_read:lda $ffff,x
.unmasked_write:sta $ff00,y

tya
adc flames_unmasked_deltas,x
tay
bcc unmasked_noc
inc unmasked_write+2
clc
.unmasked_noc

inx

cpx #flames_unmasked_writes_size
bne unmasked_loop

; masked

clc
lda ZP_12
adc #HI(flames_initial_masked_write_addr)
sta masked_read+2
sta masked_write+2

ldy #LO(flames_initial_masked_write_addr)
ldx #0

.masked_loop

.masked_read:lda $ff00,y
.masked_mask:and $ffff,x
.masked_value:ora $ffff,x
.masked_write:sta $ff00,y

tya
adc flames_masked_deltas,x
tay
bcc masked_noc
inc masked_read+2
inc masked_write+2
clc
.masked_noc

inx

cpx #flames_masked_writes_size
bne masked_loop

rts

.unmasked_tables
equw flames_unmasked_values_0
equw flames_unmasked_values_1
equw flames_unmasked_values_2

.masked_values_tables
equw flames_masked_values_0
equw flames_masked_values_1
equw flames_masked_values_2

.masked_masks_tables
equw flames_masked_masks_0
equw flames_masked_masks_1
equw flames_masked_masks_2
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

._graphics_copy_menu_header_graphic
{

if (menu_header_graphic_end-menu_header_graphic_begin) mod 256<>0
error "oops"
endif

ldx #0
.loop
for i,0,(menu_header_graphic_end-menu_header_graphic_begin) div 256-1
lda menu_header_graphic_begin+i*256,x:sta $4000+i*256,x
next

inx
bne loop

rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Redraw part of the engine on top of the wheel sprite.
MACRO REDRAW_ENGINE row0_addr,row1_addr,offset,masks,values

clc

lda #HI(row0_addr+offset):adc ZP_12:sta rd0+2:sta wr0+2

lda #HI(row1_addr+offset):adc ZP_12:sta rd1+2:sta wr1+2

ldx #23

.loop

.rd0:lda $ff00+LO(row0_addr+offset),x
and masks+0,x
ora values+0,x
.wr0:sta $ff00+LO(row0_addr+offset),x

.rd1:lda $ff00+LO(row1_addr+offset),x
and masks+24,x
ora values+24,x
.wr1:sta $ff00+LO(row1_addr+offset),x

dex
bpl loop

ENDMACRO

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; C64 version: the wheels are sprites - two sprites for the left
; wheel, and two sprites for the right. C64 sprites appear on top of
; the bitmap, so this makes the wheels appear on top of the engine. To
; fix this, there are two additional higher-priority sprites, that
; look like the nearest pair of exhaust pipes, positioned exactly on
; top of the corresponding areas of the bitmap.
; 
; The wheel sprites aren't tall enough to reach the bottom of the
; screen when the wheel is at its minimum Y coordinate, so the HUD
; graphic contains 10 or so rows of black in the bottom left and right
; corners. When the wheels is at its minimum Y coordinate, these areas
; are revealed, and it just looks like you're looking at the inside of
; the wheel.
;
;
; The BBC version is sort of similar.
;
; For the part of the wheel that overlaps the double-buffered area, it
; draws the wheel on top of the engine (writing unmasked $00 bytes if
; it runs out of wheel data before reaching the bottom of the screen
; area), then redraws the bit of the engine that could have been
; overwritten.
;
; For the single-buffered area, it does a similar sort of thing, but
; only writes each byte once to avoid flicker. There is also a
; load-bearing pixel in the last byte of the single-buffered area that
; needs to be retained.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Copy blank wheel to double-buffered area.
.wheel_blank_part
{
clc
sta ld0+1
adc #8:sta ld8+1
adc #8:sta ld16+1

ldx ZP_14

.loop
cpx #wheel_end_sprite_y:bcs done

lda wheel_row_ptrs_LO-wheel_min_sprite_y,x:sta ZP_1E
lda wheel_row_ptrs_HI-wheel_min_sprite_y,x:adc ZP_12:sta ZP_1F

inx

lda #0

.ld0:ldy #0:sta (ZP_1E),y
.ld8:ldy #8:sta (ZP_1E),y
.ld16:ldy #16:sta (ZP_1E),y

bne loop

.done
stx ZP_14
rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Blank the bottom left corner.
.wheel_blank_left_corner
{
lda #0
sta $77e0
sta $77e1
sta $77e2
sta $77e3
sta $77e4
sta $77e5
lda #hud_left_corner_byte
sta $77e6
rts
}

; Blank the bottom right corner.
.wheel_blank_right_corner
{
lda #0
sta $78d8
sta $78d9
sta $78da
sta $78db
sta $78dc
sta $78dd
lda #hud_right_corner_byte
sta $78de
rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Copy wheel data into the bottom right corner, followed by blank if
; the data runs out before the bottom of the display.
.wheel_copy_right_corner
{
lda #$d8:sta wheel_copy_corner_wr0+1:sta wheel_copy_corner_wr1+1
lda #$78:sta wheel_copy_corner_wr0+2:sta wheel_copy_corner_wr1+2
lda #hud_right_corner_byte
inx:inx							; copy from right column
jmp wheel_copy_corner
}

; Copy wheel data into the bottom left corner, followed by blank if
; the data runs out before the bottom of the display.
.wheel_copy_left_corner
{
lda #$e0:sta wheel_copy_corner_wr0+1:sta wheel_copy_corner_wr1+1
lda #$77:sta wheel_copy_corner_wr0+2:sta wheel_copy_corner_wr1+2
lda #hud_left_corner_byte
; run through into wheel_copy_corner
}

; Copy wheel data to left or right corner.
;
; Fix up wheel_copy_corner_wr0 and wheel_copy_corner_wr1 before
; calling. A is the byte to store in the bottom row.
.wheel_copy_corner
{
sta corner_values+6
ldy #0
.loop
.*wheel_copy_corner_ld:lda $ffff,x
ora corner_values,y
.*wheel_copy_corner_wr0:sta $ffff,y
inx:inx:inx
cpx #wheel_data_size:bcs out_of_data
iny
cpy #7:bne loop

rts

.out_of_data_loop
lda corner_values,y
.*wheel_copy_corner_wr1:sta $ffff,y
.out_of_data
iny
cpy #7:bne out_of_data_loop
rts

.corner_values
equb 0,0,0,0,0,0
equb 0
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Generate a wheel copy routine - copy data from DATA to left
; (IS_LEFT==TRUE) or right (IS_LEFT==FALSE) side of the screen in the
; double-buffered area.
MACRO WHEEL_ROUTINE is_left,data

if is_left
y=0
else
y=232
endif

ldx #0

.loop
ldy ZP_14

cpy #wheel_end_sprite_y:bcs reached_bottom

lda wheel_row_ptrs_LO-wheel_min_sprite_y,y:sta ZP_1E
lda wheel_row_ptrs_HI-wheel_min_sprite_y,y:adc ZP_12:sta ZP_1F

iny:sty ZP_14

ldy #y+0
lda (ZP_1E),y:and data,x:ora data+wheel_data_size,x:sta (ZP_1E),y
inx

ldy #y+8
lda (ZP_1E),y:and data,x:ora data+wheel_data_size,x:sta (ZP_1E),y
inx

ldy #y+16
lda (ZP_1E),y:and data,x:ora data+wheel_data_size,x:sta (ZP_1E),y
inx

cpx #wheel_data_size
bne loop

; Out of data.

lda #y:jsr wheel_blank_part

; And blank out the bottom corner bit too.
if is_left
jsr wheel_blank_left_corner
else
jsr wheel_blank_right_corner
endif

rts

.reached_bottom

lda #LO(data+wheel_data_size):sta wheel_copy_corner_ld+1
lda #HI(data+wheel_data_size):sta wheel_copy_corner_ld+2

if is_left
jsr wheel_copy_left_corner
else
jsr wheel_copy_right_corner
endif

rts
ENDMACRO

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

._graphics_draw_left_wheel_0:WHEEL_ROUTINE TRUE,wheel_left_0_data
._graphics_draw_left_wheel_1:WHEEL_ROUTINE TRUE,wheel_left_1_data
._graphics_draw_left_wheel_2:WHEEL_ROUTINE TRUE,wheel_left_2_data

._graphics_draw_left_wheel_LO
equb LO(_graphics_draw_left_wheel_0)
equb LO(_graphics_draw_left_wheel_1)
equb LO(_graphics_draw_left_wheel_2)

._graphics_draw_left_wheel_HI
equb HI(_graphics_draw_left_wheel_0)
equb HI(_graphics_draw_left_wheel_1)
equb HI(_graphics_draw_left_wheel_2)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

._graphics_draw_right_wheel_0:WHEEL_ROUTINE FALSE,wheel_right_0_data
._graphics_draw_right_wheel_1:WHEEL_ROUTINE FALSE,wheel_right_1_data
._graphics_draw_right_wheel_2:WHEEL_ROUTINE FALSE,wheel_right_2_data

._graphics_draw_right_wheel_LO
equb LO(_graphics_draw_right_wheel_0)
equb LO(_graphics_draw_right_wheel_1)
equb LO(_graphics_draw_right_wheel_2)

._graphics_draw_right_wheel_HI
equb HI(_graphics_draw_right_wheel_0)
equb HI(_graphics_draw_right_wheel_1)
equb HI(_graphics_draw_right_wheel_2)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

MACRO WHEEL_PUSH 
lda ZP_14:pha
lda ZP_1E:pha
lda ZP_1F:pha
ENDMACRO

MACRO WHEEL_POP
pla:sta ZP_1F
pla:sta ZP_1E
pla:sta ZP_14
ENDMACRO

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


._graphics_draw_left_wheel
{
WHEEL_PUSH

sty ZP_14

lda _graphics_draw_left_wheel_LO,x:sta call+1
lda _graphics_draw_left_wheel_HI,x:sta call+2
.call jsr $ffff

REDRAW_ENGINE $5540,$5680,4*8,engine_left_masks,engine_left_values

WHEEL_POP

rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

._graphics_draw_right_wheel
{
WHEEL_PUSH

sty ZP_14

lda _graphics_draw_right_wheel_LO,x:sta call+1
lda _graphics_draw_right_wheel_HI,x:sta call+2
.call jsr $ffff

REDRAW_ENGINE $5540,$5680,33*8,engine_right_masks,engine_right_values

WHEEL_POP

rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; The text areas are not really very conveniently aligned :(
;
; 6 scanlines to write.
;
; Scanlines 0/1/2 are always on the same character row, and scanline 5
; is always on a different character row from 0/1/2.
;
;     NW    SW    NE    SE
; 0  7bab  7ced  7c6b  7dad
; 1  7bac  7cee  7c6c  7dae
; 2  7bad  7cef  7c6d  7daf
; 3  7bae  7e28  7c6e  7ee8
; 4  7baf  7e29  7c6f  7ee9
; 5  7ce8  7e2a  7da8  7eea

dash_ZP_ptr0=ZP_1E
dash_ZP_ptr1=ZP_20
dash_ZP_ptr2=ZP_22
dash_ZP_offset=ZP_24
dash_ZP_tmp=ZP_25

MACRO PREPARE_ROUTINE addr_012,addr_34,addr_5
lda #LO(addr_012):sta dash_ZP_ptr0+0
lda #HI(addr_012):sta dash_ZP_ptr0+1

lda #LO(addr_34):sta dash_ZP_ptr1+0
lda #HI(addr_34):sta dash_ZP_ptr1+1

lda #LO(addr_5):sta dash_ZP_ptr2+0
lda #HI(addr_5):sta dash_ZP_ptr2+1

lda #0:sta dash_ZP_offset

rts
ENDMACRO

.dash_buffer:skip 6

.dash_prepare_for_nw:PREPARE_ROUTINE $7bab,$7bae,$7ce8
.dash_prepare_for_sw:PREPARE_ROUTINE $7ced,$7e28,$7e2a
.dash_prepare_for_ne:PREPARE_ROUTINE $7c6b,$7c6e,$7da8
.dash_prepare_for_se:PREPARE_ROUTINE $7dad,$7ee8,$7eea

.dash_clearbuf
{
lda #$ff
sta dash_buffer+0
sta dash_buffer+1
sta dash_buffer+2
sta dash_buffer+3
sta dash_buffer+4
sta dash_buffer+5
rts
}

.dash_loadbuf
{
ldy dash_ZP_offset

; +0
lda (dash_ZP_ptr0),y:sta dash_buffer+0
lda (dash_ZP_ptr1),y:sta dash_buffer+3
lda (dash_ZP_ptr2),y:sta dash_buffer+5

; +1
iny
lda (dash_ZP_ptr0),y:sta dash_buffer+1
lda (dash_ZP_ptr1),y:sta dash_buffer+4

; +2
iny
lda (dash_ZP_ptr0),y:sta dash_buffer+2

rts
}

.dash_storebuf
{
ldy dash_ZP_offset

; +0
lda dash_buffer+0:sta (dash_ZP_ptr0),y
lda dash_buffer+3:sta (dash_ZP_ptr1),y
lda dash_buffer+5:sta (dash_ZP_ptr2),y

; +1
iny
lda dash_buffer+1:sta (dash_ZP_ptr0),y
lda dash_buffer+4:sta (dash_ZP_ptr1),y

; +2
iny
lda dash_buffer+2:sta (dash_ZP_ptr0),y

clc:tya:adc #6:sta dash_ZP_offset
rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; storech - overwrite dash_buffer with char (or part thereof).

.dash_storech_0_and_storebuf
{
lda #LO(hud_font_shift0):sta dash_storech_read_table+1
lda #HI(hud_font_shift0):sta dash_storech_read_table+2
jsr dash_storech
jmp dash_storebuf
}

.dash_storech_2l_and_storebuf
{
lda #LO(hud_font_shift2_a):sta dash_storech_read_table+1
lda #HI(hud_font_shift2_a):sta dash_storech_read_table+2
jsr dash_storech
jmp dash_storebuf
}

.dash_storech_2r
{
lda #LO(hud_font_shift2_b):sta dash_storech_read_table+1
lda #HI(hud_font_shift2_b):sta dash_storech_read_table+2
}
.dash_storech
{
ldy #5
.loop
sty reload_y+1
ldy hud_font,x
.*dash_storech_read_table:lda $ffff,y
.reload_y:ldy #$ff
sta dash_buffer,y
inx
dey						
bpl loop				
rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; addch - add char (or part thereof), masked, into existing contents
; of dash_buffer.

.dash_addch_2l_and_storebuf
{
lda #$33:sta dash_addch_mask+1
lda #LO(hud_font_shift2_a):sta dash_addch_read_table+1
lda #HI(hud_font_shift2_a):sta dash_addch_read_table+2
jsr dash_addch
jmp dash_storebuf
}

.dash_addch_2r
{
lda #$cc:sta dash_addch_mask+1
lda #LO(hud_font_shift2_b):sta dash_addch_read_table+1
lda #HI(hud_font_shift2_b):sta dash_addch_read_table+2
}
.dash_addch
{
ldy #5
.loop
lda dash_buffer,y
.*dash_addch_mask:ora #$ff
sty reload_y+1
ldy hud_font,x
.*dash_addch_read_table:and $ffff,y
.reload_y:ldy #$ff
sta dash_buffer,y
inx
dey
bpl loop
rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; stores right half of whatever's in dash_ZP_tmp, left half of X, and
; puts X in dash_ZP_tmp ready for the next call.
.dash_storech_2_and_storebuf
{
stx reload_x+1
ldx dash_ZP_tmp:jsr dash_storech_2r
.reload_x:ldx #$ff
stx dash_ZP_tmp
jmp dash_addch_2l_and_storebuf
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.high_nybble_digit
{
and #$f0						; x*16
lsr a							; x*8
lsr a							; x*4
sta add+1
lsr a							; x*2
.add:adc #$ff					; x*2+x*4
tax
rts
}

.low_nybble_digit
and #$0f
.digit
{
and #%00111111
asl a
sta add+1
asl a
.add:adc #$ff
tax
rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; 5 unmasked columns + 2 pixels.
.dash_clear_west
{
jsr dash_clear_5_columns_unmasked
lda #$cc
}
.dash_clear_1_column_masked
{
sta mask+1
jsr dash_loadbuf
ldx #5
.loop
lda dash_buffer,x
.mask:ora #$ff
sta dash_buffer,x
dex
bpl loop
jmp dash_storebuf
}

; 2 pixels + 5 unmasked columns.
.dash_clear_east
{
lda #$33:jsr dash_clear_1_column_masked
}
.dash_clear_5_columns_unmasked
{
jsr dash_clearbuf
ldx #5
.loop
jsr dash_storebuf
dex
bne loop
rts
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

._dash_reset
{
jsr dash_save_zp

; NW - lap/boost
jsr dash_prepare_for_nw:jsr dash_clear_west

lda #0:sta dash_ZP_offset

ldx #hud_font_char_L:jsr dash_storech_0_and_storebuf

lda #16:sta dash_ZP_offset

ldx #hud_font_char_B:jsr dash_storech_2l_and_storebuf
ldx #hud_font_char_B:jsr dash_storech_2r:jsr dash_storebuf

; SW - aicar distance
jsr dash_prepare_for_sw:jsr dash_clear_west

; NE - lap time
jsr dash_prepare_for_ne:jsr dash_clear_east

; SE - best lap
jsr dash_prepare_for_se:jsr dash_clear_east

jmp dash_restore_zp
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

._dash_update_boost
{
jsr dash_save_zp

jsr dash_prepare_for_nw

lda #3*8:sta dash_ZP_offset

lda #hud_font_char_B:sta dash_ZP_tmp

; 'B' (right half) + Boost reserve high nybble (left half)
lda boost_reserve:jsr high_nybble_digit:jsr dash_storech_2_and_storebuf

;Boost reserve high nybble (right half) + boost reserve low nybble
;(left half)
lda boost_reserve:jsr low_nybble_digit:jsr dash_storech_2_and_storebuf

; Boost reserve low nybble (right half)
jsr dash_loadbuf
ldx dash_ZP_tmp:jsr dash_addch_2r
jsr dash_storebuf

jmp dash_restore_zp
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

._dash_update_lap
{
jsr dash_save_zp
jsr dash_prepare_for_nw

lda #1*8:sta dash_ZP_offset

ldx #hud_font_char_space
lda L_C378:beq storech
jsr digit
.storech
jsr dash_storech_0_and_storebuf

jmp dash_restore_zp
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

._dash_update_distance_to_ai_car
{
jsr dash_save_zp
jsr dash_prepare_for_sw

ldx #hud_font_char_space
lda L_C36A
and #$f0
bpl prefix
ldx #hud_font_char_minus
.prefix
stx dash_ZP_tmp

jsr dash_storech_2l_and_storebuf

lda ZP_18:jsr digit:jsr dash_storech_2_and_storebuf
lda ZP_16:jsr digit:jsr dash_storech_2_and_storebuf
lda ZP_15:jsr digit:jsr dash_storech_2_and_storebuf
lda ZP_17:jsr digit:jsr dash_storech_2_and_storebuf

jsr dash_loadbuf
ldx dash_ZP_tmp:jsr dash_addch_2r
jsr dash_storebuf

jmp dash_restore_zp
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; .graphics_update_aicar_distance
; {
; ; - or space
; ldx #hud_font_char_space
; lda #$f0
; bit L_C36A						; distance_to_aicar_in_segments
; bpl print
; ldx #hud_font_char_minus
; .print
; jsr graphics_store_char_0
; jsr graphics_store_hud

; lda byte_18:jsr digit:jsr graphics_store_char_shift0:jsr graphics_store_hud
; lda byte_16:jsr digit:jsr graphics_store_char_shift0:jsr graphics_store_hud
; lda byte_15:jsr digit:jsr graphics_store_char_shift0:jsr graphics_store_hud
; lda byte_17:jsr digit:jsr graphics_store_char_shift0:jsr graphics_store_hud

; rts
; }

.dash_save_zp
{
lda dash_ZP_offset:sta dash_restore_zp_reload_offset+1
lda dash_ZP_tmp:sta dash_restore_zp_reload_tmp+1
lda dash_ZP_ptr0+0:sta dash_restore_zp_reload_ptr0_0+1
lda dash_ZP_ptr0+1:sta dash_restore_zp_reload_ptr0_1+1
lda dash_ZP_ptr1+0:sta dash_restore_zp_reload_ptr1_0+1
lda dash_ZP_ptr1+1:sta dash_restore_zp_reload_ptr1_1+1
lda dash_ZP_ptr2+0:sta dash_restore_zp_reload_ptr2_0+1
lda dash_ZP_ptr2+1:sta dash_restore_zp_reload_ptr2_1+1
rts
}

.dash_restore_zp
{
.*dash_restore_zp_reload_offset:lda #$ff:sta dash_ZP_offset
.*dash_restore_zp_reload_tmp:lda #$ff:sta dash_ZP_tmp
.*dash_restore_zp_reload_ptr0_0:lda #$ff:sta dash_ZP_ptr0+0
.*dash_restore_zp_reload_ptr0_1:lda #$ff:sta dash_ZP_ptr0+1
.*dash_restore_zp_reload_ptr1_0:lda #$ff:sta dash_ZP_ptr1+0
.*dash_restore_zp_reload_ptr1_1:lda #$ff:sta dash_ZP_ptr1+1
.*dash_restore_zp_reload_ptr2_0:lda #$ff:sta dash_ZP_ptr2+0
.*dash_restore_zp_reload_ptr2_1:lda #$ff:sta dash_ZP_ptr2+1
rts
}

.beeb_graphics_end
