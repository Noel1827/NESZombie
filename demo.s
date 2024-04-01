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
SPRITE_BUFFER = $0200

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
; Args for render_sprite subroutine
render_x: .res 1
render_y: .res 1
render_tile: .res 1
available_oam: .res 1

; Animation vars
direction: .res 1 ; 0 = up, 1 = down, 2 = left, 3 = right
animState: .res 1 ; 0 = first frame, 1 = second frame, 2 = third frame
frameCounter: .res 1 ; Counter for frames
vblank_flag: .res 1 ; Flag for vblank

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

    ldx #100
    stx x_coord
    ldy #90
    sty y_coord

    ldx #0
    render_initial_sprites_loop:
        lda x_coord
        sta render_x
        lda y_coord
        sta render_y
        lda left_tank_tiles, x
        sta render_tile
        jsr render_sprite
        inx
        lda x_coord
        clc
        adc #16
        sta x_coord

        cpx #4
        bne render_initial_sprites_loop

enable_rendering:
  lda #%10000000	; Enable NMI
  sta PPUCTRL
  lda #%00010110; Enable background and sprite rendering in PPUMASK.
  sta PPUMASK

forever:
  jsr update_sprites
  jmp forever

nmi:
  ; Set vblank_flag to 1
  lda #1
  sta vblank_flag

  ; Start OAMDMA transfer
  lda #$02          ; High byte of $0200 where SPRITE_BUFFER is located.
  sta OAMDMA         ; Writing to OAMDMA register initiates the transfer.


  lda frameCounter ; Load frameCounter
  cmp #30 ; Compare frameCounter to 60
  bne skip_reset_timer ; If frameCounter is not 60, skip resetting it
  lda #$00 ; Reset frameCounter to 0
  sta frameCounter ; Store 0 in frameCounter

  skip_reset_timer: ; Skip resetting frameCounter and render_sprite subroutine
  inc frameCounter ; Increase frameCounter by 1

  ; Reset scroll position
  lda #$00
  sta PPUSCROLL
  lda #$00
  sta PPUSCROLL

  rti

render_sprite:
  lda PPUSTATUS
  ; Render first tile of the sprite
    jsr render_tile_subroutine  ; Call render_tile subroutine

    ; Render second tile of the sprite
    lda render_x
    clc
    adc #$08
    sta render_x ; x = x + 8
    lda render_tile
    clc
    adc #$01
    sta render_tile
    jsr render_tile_subroutine  ; Call render_tile subroutine

    ; Render third tile of the sprite
    lda render_y
    clc
    adc #$08
    sta render_y ; y = y + 8

    lda render_tile
    clc
    adc #$10
    sta render_tile
    jsr render_tile_subroutine  ; Call render_tile subroutine

    ; Render fourth tile of the sprite
    ; No need to update y since it's already at the bottom of the sprite
    ; Only update x to move left by 8 pixels
    lda render_x
    sbc #8 ; WHY DOES THIS RESULT IS 0X4F (0X58 - 8) ITS SUPPOSED TO BE 0X50
    tay
    iny 
    sty render_x ; x = x - 8

    ldy render_tile 
    dey
    sty render_tile
    jsr render_tile_subroutine  ; Call render_tile subroutine

    RTS
; Render a single tile of the sprite
render_tile_subroutine:
    ldx available_oam ; Offset for OAM buffer

    lda render_y
    sta SPRITE_BUFFER, x ; Store y position of the sprite
    inx

    lda render_tile
    sta SPRITE_BUFFER, x
    inx

    lda #$00
    sta SPRITE_BUFFER, x
    inx

    lda render_x
    sta SPRITE_BUFFER, x
    inx

    stx available_oam ; Update available_oam to the next available OAM buffer index`

    rts
  
update_sprites:
    ; Exit subroutine if frameCounter is not 29
    lda frameCounter
    cmp #29
    bne skip_update_sprites

    ; Dont update sprites if vblank_flag is not set
    lda vblank_flag
    cmp #1
    bne skip_update_sprites

    ; Update sprites

    ; If animState is 2, reset animState to 0 and reset sprites to first frame
    lda animState
    cmp #2
    bne skip_reset_animState

    ; Reset animState to 0
    lda #$00
    sta animState

    ; Reset sprites to first frame
    ldx #9 ; offset for buffer, where the tile data for tile 1 is stored
    ldy #0
    reset_sprites_loop:
    lda SPRITE_BUFFER, x ; Load tile data for tile y
    clc
    sbc #3 ; Add 2 to the tile data to change the sprite to the next frame
    sta SPRITE_BUFFER, x ; Store the updated tile data back to the buffer
    txa ; Load x to a
    clc
    adc #4 ; Add 4 to x to move to the next tile data
    tax ; Store the updated x back to x
    iny ; Increase y by 1
    cpy #16
    bne reset_sprites_loop ; If y is not 16, loop back to reset_sprites_loop, since we have reset updated all sprites

    ; Skip updating sprites since we just reset them
    jmp skip_update_sprites

    skip_reset_animState:
    ; Update animation state
    lda animState
    clc
    adc #1
    sta animState

    ldx #9 ; offset for buffer, where the tile data for tile 1 is stored
    ldy #0
    update_sprites_loop:
    lda SPRITE_BUFFER, x ; Load tile data for tile y
    clc
    adc #2 ; Add 2 to the tile data to change the sprite to the next frame
    sta SPRITE_BUFFER, x ; Store the updated tile data back to the buffer

    txa ; Load x to a
    clc
    adc #4 ; Add 4 to x to move to the next tile data
    tax ; Store the updated x back to x
    iny ; Increase y by 1
    cpy #16
    bne update_sprites_loop ; If y is not 16, loop back to update_sprites_loop, since we have not updated all sprites

    lda #$00 ; Reset vblank_flag
    sta vblank_flag

    skip_update_sprites:
    rts

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

left_tank_tiles:
.byte $02, $06, $22, $26

; Character memory
.segment "CHARS"
.incbin "tanks.chr"