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

  JSR sprites_loop

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

  load_name_table:
        lda PPUSTATUS
        lda #$20
        sta PPUADDR
        lda #$8C
        sta PPUADDR

        ldx #$00
        @loop1:
            lda name_table, x
            sta PPUDATA
            inx
            cpx #$06
            bne @loop1
        
        lda #$20
        sta PPUADDR
        lda #$ac
        sta PPUADDR

        @loop2:
            lda name_table, x
            sta PPUDATA
            inx
            cpx #12
            bne @loop2
        
        ; lda #$22
        ; sta PPUADDR
        ; lda #$cc
        ; sta PPUADDR

        ; @loop3:
        ;     lda name_table, x
        ;     sta PPUDATA
        ;     inx
        ;     cpx #24
        ;     bne @loop3
        
        ; lda #$22
        ; sta PPUADDR
        ; lda #$ec
        ; sta PPUADDR

        ; @loop4:
        ;     lda name_table, x
        ;     sta PPUDATA
        ;     inx
        ;     cpx #32
        ;     bne @loop4     

enable_rendering:
  lda #%10010000	; Enable NMI
  sta PPUCTRL
  lda #%00011110; Enable background and sprite rendering in PPUMASK.
  sta PPUMASK

forever:
  jmp forever

sprites_loop:
  ldx #0                ; Initialize index to 0
  ldy #0                ; Y counter for sprites in the current row

loop_start:
  lda sprites, x        ; Load Y position of sprite into A
  sta pos_y             ; Store Y position in pos_y
  lda sprites+1, x      
  sta tile_num          ; Store tile number in tile_num
  lda sprites+3, x      
  sta pos_x             ; Store X position in pos_x

  jsr render_sprite     ; Call the subroutine to render the sprite
  inx
  inx
  inx
  inx
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

name_table:
.byte $02, $03, $04, $05, $06, $07
.byte $12, $13, $14, $15, $16, $17

sprites:
.byte $64, $02, $00, $64  
.byte $64, $03, $00, $6C 
.byte $6C, $12, $00, $64 
.byte $6C, $13, $00, $6C 

.byte $64, $04, $00, $74 
.byte $64, $05, $00, $7C 
.byte $6C, $14, $00, $74
.byte $6C, $15, $00, $7C 

.byte $64, $06, $00, $84 
.byte $64, $07, $00, $8C
.byte $6C, $16, $00, $84
.byte $6C, $17, $00, $8C

.byte $64, $08, $00, $94
.byte $64, $09, $00, $9C
.byte $6C, $18, $00, $94
.byte $6C, $19, $00, $9C

.byte $74, $22, $00, $64 
.byte $74, $23, $00, $6C
.byte $7C, $32, $00, $64 
.byte $7C, $33, $00, $6C

.byte $74, $24, $00, $74
.byte $74, $25, $00, $7C
.byte $7C, $34, $00, $74
.byte $7C, $35, $00, $7C

.byte $74, $26, $00, $84
.byte $74, $27, $00, $8C
.byte $7C, $36, $00, $84
.byte $7C, $37, $00, $8C

.byte $74, $28, $00, $94
.byte $74, $29, $00, $9C
.byte $7C, $38, $00, $94
.byte $7C, $39, $00, $9C


; Character memory
.segment "CHARS"
.incbin "zombies.chr"
