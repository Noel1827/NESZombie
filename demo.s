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
sprite_buffer = $0200


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
; Args for prepare_sprites subroutine
render_x: .res 1
render_y: .res 1

render_tile: .res 1
oam_offset: .res 1

; Animation state for sprites
count_frames: .res 1 
animation: .res 1 
vblank_flag: .res 1 ; Flag for vblank

; Args for prepare_sprites subroutine
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
    stx pos_x
    ldy #90
    sty pos_y

    ldy #0
    prepare_spritess_loop:
        lda pos_y
        sta render_y ; Store y position of the sprite
        lda pos_x
        sta render_x ; Store x position of the sprite
        lda left_tank_tiles, y ; Load tile number of the sprite

        sta render_tile
        jsr prepare_sprites

        iny
        lda pos_x
        clc
        adc #16
        sta pos_x

        cpy #4
        bne prepare_spritess_loop

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
  lda #$02         
  sta OAMDMA        


  lda count_frames ; Load count_frames
  cmp #30 ; Compare count_frames to 30
  bne jmp_rst_timer ; If count_frames is not 60, skip resetting it
  lda #$00 ; Reset count_frames to 0
  sta count_frames ; Store 0 in count_frames

  jmp_rst_timer: ; Skip resetting count_frames and prepare_sprites subroutine
  inc count_frames ; Increase count_frames by 1

  ; Reset scroll position
  lda #$00
  sta PPUSCROLL
  lda #$00
  sta PPUSCROLL

  rti

prepare_sprites:
    pha
    txa
    pha
    tya
    pha
  
    jsr store_in_sprite_buffer  

    ; Render second tile of the sprite
    lda render_x
    clc
    adc #$08
    sta render_x ; x = x + 8
    lda render_tile
    clc
    adc #$01 ; Load next tile of the sprite
    sta render_tile
    jsr store_in_sprite_buffer  

    ; Render third tile of the sprite
    lda render_y
    clc
    adc #$08
    sta render_y ; y = y + 8

    lda render_tile
    clc
    adc #$10
    sta render_tile
    jsr store_in_sprite_buffer  

    ; Render fourth tile of the sprite
    ; Only update x to move left by 8 pixels
    lda render_x
    sbc #8 
    tay
    iny 
    sty render_x ; x = x - 8

    ldy render_tile 
    dey
    sty render_tile
    jsr store_in_sprite_buffer  

    pla
    tay
    pla
    tax
    pla
    
    RTS
; Render a single tile of the sprite
store_in_sprite_buffer:
    ldx oam_offset ; Offset for OAM buffer

    lda render_y
    sta sprite_buffer, x ; Store y position of the sprite
    inx

    lda render_tile
    sta sprite_buffer, x
    inx

    lda #$00
    sta sprite_buffer, x
    inx

    lda render_x
    sta sprite_buffer, x
    inx

    stx oam_offset ; Update oam_offset to the next available OAM buffer index`

    rts
  
update_sprites:
    ; Exit subroutine if count_frames is not 29
    lda count_frames
    cmp #29
    bne skip_update_sprites

    ; Dont update sprites if vblank_flag is not set
    lda vblank_flag
    cmp #1
    bne skip_update_sprites

    ; If animation is 1, reset animation and reset sprites to first frame
    lda animation
    cmp #1
    bne skip_reset_animation

    ; Reset animation 
    lda #$00
    sta animation

    ; Reset sprites to first frame
    ldx #1 ; offset for buffer, where the tile data for tile 1 is stored
    ldy #0 
    reset_sprites_loop:
    lda sprite_buffer, x ; Load tile data for tile y
    clc
    sbc #1 ; Add 1 to the tile data to change the sprite to the next frame
    sta sprite_buffer, x ; Store the updated tile data back to the buffer
    txa ; Load x to a
    clc
    adc #4 ; Add 4 to x to move to the next tile data
    tax ; Store the updated x back to x
    iny ; Increase y by 1
    cpy #16
    bne reset_sprites_loop ; If y is not 16, loop back to reset_sprites_loop, since we have reset updated all sprites

    ; Skip updating sprites since we just reset them
    jmp skip_update_sprites

    skip_reset_animation:
    ; Update animation state
    lda animation
    clc
    adc #1
    sta animation

    ldx #1 ; offset for buffer, where the tile data for tile 1 is stored
    ldy #0
    update_sprites_loop:
    lda sprite_buffer, x ; Load tile data for tile y
    clc
    adc #2 ; Add 2 to the tile data to change the sprite to the next frame
    sta sprite_buffer, x ; Store the updated tile data back to the buffer

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