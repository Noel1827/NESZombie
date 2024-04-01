; Noel Andres Vargas Padilla 801-19-7297
PPUCTRL   = $2000
PPUSCROLL = $2005
PPUMASK   = $2001
PPUSTATUS = $2002
PPUADDR   = $2006
PPUDATA   = $2007
OAMADDR   = $2003
OAMDMA    = $4014
OAMDATA = $2004

CONTROLLER1 = $4016
CONTROLLER2 = $4017

BTN_RIGHT   = %00000001
BTN_LEFT    = %00000010
BTN_DOWN    = %00000100
BTN_UP      = %00001000
BTN_START   = %00010000
BTN_SELECT  = %00100000
BTN_B       = %01000000
BTN_A       = %10000000

.segment "HEADER"
  ; .byte "NES", $1A      ; iNES header identifier
  .byte $4E, $45, $53, $1A
  .byte 2               ; 2x 16KB PRG code
  .byte 1               ; 1x  8KB CHR data
  .byte $01, $00        ; mapper 0, vertical mirroring

.segment "VECTORS"
  ;; When an NMI happens (once per frame if enabled) the label nmi:
  .addr nmi
  ;; When the processor first turns on or is reset, it will jump to the label reset:
  .addr reset
  ;; External interrupt IRQ (unused)
  .addr 0

; "nes" linker config requires a STARTUP section, even if it's empty
.segment "STARTUP"

.segment "ZEROPAGE"
; Address trackers
curr_oam_addr: .res 1

; Args for render_sprite subroutine
pos_x: .res 1
pos_y: .res 1
tile_num: .res 1



; Main code segment for the program
.segment "CODE"

reset:
  sei		; disable IRQs
  cld		; disable decimal mode
  ldx #$40
  stx $4017	; disable APU frame IRQ
  ldx #$ff 	; Set up stack
  txs		;  .
  inx		; now X = 0
  stx PPUCTRL	; disable NMI
  stx PPUMASK 	; disable rendering
  stx $4010 	; disable DMC IRQs

;; first wait for vblank to make sure PPU is ready
vblankwait1:
  bit PPUSTATUS
  bpl vblankwait1

clear_memory:
  lda #$00
  sta $0000, x
  sta $0100, x
  sta $0200, x
  sta $0300, x
  sta $0400, x
  sta $0500, x
  sta $0600, x
  sta $0700, x
  inx
  bne clear_memory
  
;; second wait for vblank, PPU is ready after this
vblankwait2:
  bit PPUSTATUS
  bpl vblankwait2

main:

  clear_oam:
    ldx #0
    loop_clear_oam:
      lda #$FF ; load byte x of sprite list
      sta OAMDATA ; 
      inx
      cpx #255
      bne loop_clear_oam
      
  lda #$10
  sta pos_x
  sta pos_y
  ; num of sprites
  ldx #08
  ; num of sprites per row
  ldy #04

  lda #$02
  sta tile_num
  JSR sprites_loop

  ; JSR read_controller1
  ; JSR update_player

  load_palettes:
    lda PPUSTATUS
    lda #$3f
    sta PPUADDR
    lda #$00
    sta PPUADDR

    ldx #$00
    @loop:
      lda palettes, x
      sta PPUDATA
      inx
      cpx #$20
      bne @loop

enable_rendering:
  lda #%10000000	; Enable NMI
  sta PPUCTRL
  lda #%00010110; Enable background and sprite rendering in PPUMASK.
  sta PPUMASK

forever:
  jmp forever

sprites_loop:
  ldx #0                ; Initialize index to 0
  ldy #0                ; Y counter for sprites in the current row

loop_start:
  lda sprites, x        ; Load Y position of sprite into A
  sta pos_y             ; Store Y position in pos_y
  lda sprites+1, x      ; Load tile number of sprite into A
  sta tile_num          ; Store tile number in tile_num
  lda sprites+3, x      ; Load X position of sprite (skipping attribute byte)
  sta pos_x             ; Store X position in pos_x

  jsr render_sprite     ; Call the subroutine to render the sprite

  iny                   ; Increment sprite row counter
  cpy #4                ; Check if 4 sprites have been rendered in the current row
  bne skip_row_adjust   ; If not, skip the Y position adjustment

  ; Adjust Y position for next row of sprites
  lda pos_y             ; Get the current Y position
  clc                   ; Clear carry flag for addition
  adc #16               ; Add 16 to Y position (moving down after a row of 4 sprites)
  sta pos_y             ; Update pos_y for the next row

skip_row_adjust: 
  inx                   ; Move to the next byte in the sprite data
  inx                   ; Skip the unused attribute byte
  inx
  inx                   ; Completed one sprite, move to the next sprite data
  cpx #(4*32)           ; Check if we've reached the end of the sprites data (4 bytes * 32 sprites)
  bne loop_start        ; If not, loop again
  rts                   


render_sprite:
  lda PPUSTATUS

  ; Load current OAM address
  lda curr_oam_addr
  sta OAMADDR

  ; Write first tile of selected sprite
  lda pos_y
  sta OAMDATA
  lda tile_num
  sta OAMDATA
  lda #$00
  sta OAMDATA
  lda pos_x
  sta OAMDATA

  ; Write second tile of selected sprite
  ; Increase pos_y by 8
  lda pos_y
  clc
  adc #8
  sta OAMDATA
  ; Increase tile_num by 16 (next tile down) 
  lda tile_num
  clc
  adc #16
  sta OAMDATA
  ; Default palette
  lda $00
  sta OAMDATA
  ; Leave x untouched, tile directly under 1st tile has same x coordinate
  lda pos_x
  sta OAMDATA

  ; Write third tile of selected sprite (directly right of 1st tile)
  ; pos_y is the same as the first tile
  lda pos_y
  sta OAMDATA
  ; Increase tile_num by 1 (next tile to the right)
  lda tile_num
  clc
  adc #1
  sta OAMDATA
  ; Default palette
  lda $00
  sta OAMDATA
  ; Increase x by 8
  lda pos_x
  clc
  adc #8
  sta OAMDATA

  ; Write fourth tile of selected sprite (directly right of 2nd tile)
  ; pos_y is increased by 8
  lda pos_y
  clc
  adc #8
  sta OAMDATA
  ; Increase tile_num by 16 + 1 (next tile to the right)
  lda tile_num
  clc
  adc #17
  sta OAMDATA
  ; Default palette
  lda $00
  sta OAMDATA
  ; Increase x by 8
  lda pos_x
  clc
  adc #8
  sta OAMDATA

  ; Save new OAM address
  lda curr_oam_addr
  clc
  adc #4
  sta curr_oam_addr
  rts

nmi:
  lda #$00
  sta PPUSCROLL
  lda #$00
  sta PPUSCROLL

  rti

palettes:
; background palette
.byte $0F, $16, $13, $37
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00

; sprite palette
.byte $0F, $16, $13, $37
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00

sprites:
.byte $00, $02, $00, $00
.byte $00, $03, $00, $08
.byte $08, $12, $00, $00
.byte $08, $13, $00, $08

.byte $00, $04, $00, $10
.byte $00, $05, $00, $18
.byte $08, $14, $00, $10
.byte $08, $15, $00, $18

.byte $00, $06, $00, $20
.byte $00, $07, $00, $28
.byte $08, $16, $00, $20
.byte $08, $17, $00, $28

.byte $00, $08, $00, $30
.byte $00, $09, $00, $38
.byte $08, $18, $00, $30
.byte $08, $19, $00, $38

.byte $18, $22, $00, $00
.byte $18, $23, $00, $08
.byte $20, $32, $00, $00
.byte $20, $33, $00, $08

.byte $18, $24, $00, $10
.byte $18, $25, $00, $18
.byte $20, $34, $00, $10
.byte $20, $35, $00, $18

.byte $18, $26, $00, $20
.byte $18, $27, $00, $28
.byte $20, $36, $00, $20
.byte $20, $37, $00, $28

.byte $18, $28, $00, $30
.byte $18, $29, $00, $38
.byte $20, $38, $00, $30
.byte $20, $39, $00, $38

; Character memory
.segment "CHARS"
.incbin "tanks.chr"