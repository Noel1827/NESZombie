; Noel Andres Vargas pad1illa 801-19-7297
PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007

OAMADDR   = $2003
OAMDATA   = $2004
OAMDMA    = $4014

sprite_buffer = $0200

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

SPRITE_Y_BASE_ADDR = $00
SPRITE_TILE_BASE_ADDR = $01
SPRITE_ATTR_BASE_ADDR = $02
SPRITE_X_BASE_ADDR = $03


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
isMoving: .res 1
changed_direction: .res 1

offset_static_sprite: .res 1
direction: .res 1

; Args for prepare_sprites subroutine
pos_x: .res 1
pos_y: .res 1
tile_num: .res 1

pad1: .res 1


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

; initialize 
 ldx #0
 stx offset_static_sprite
 stx direction
 stx animation
 stx count_frames
 stx isMoving
 stx vblank_flag
  stx changed_direction
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

    lda pos_y
    sta render_y ; Store y position of the sprite
    lda pos_x
    sta render_x ; Store x position of the sprite
    lda left_tank_tiles, y ; Load tile number of the sprite

    sta render_tile
    jsr prepare_sprites


enable_rendering:
  lda #%10000000	; Enable NMI
  sta PPUCTRL
  lda #%00010110; Enable background and sprite rendering in PPUMASK.
  sta PPUMASK

forever:
  lda vblank_flag
  cmp #1
  bne not_sync
    jsr handle_input
    jsr update_player
    jsr update_sprites
  not_sync:
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
handle_input:
    lda #$01
    sta CONTROLLER1  ; Latch the controller state
    lda #$00
    sta CONTROLLER1  ; Complete the latch process

    lda #$00
    sta pad1    ; Initialize 'pad' to 0

    ldx #$08   ; Prepare to read 8 buttons

    read_button_loop:
        lda CONTROLLER1       ; Read a button state
        lsr             ; Shift right, moving the button state into the carry
        rol pad1         ; Rotate left through carry, moving the carry into 'pad'
        dex             ; Decrement the count
        bne read_button_loop  ; Continue until all 8 buttons are read

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

    lda isMoving
    cmp #0
    beq reset_state_animation
    jmp skip_reset_animation
    reset_state_animation:
    ; Reset animation 
    lda #$00
    sta animation
    jmp skip_update_sprites

    skip_reset_animation:
    ; Update animation state
    lda animation
    clc
    adc #1
    sta animation

    cmp #2 ; Check if animation is at the last frame
    bcc animate
    lda #0
    sta animation
    jsr NOAnimated_sprite
    jmp skip_update_sprites
    

  animate:
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
    inc animation

    skip_update_sprites:
    lda #$00 ; Reset vblank_flag
    sta vblank_flag
    rts

update_player:

    ; Assume no movement initially
    lda #0
    sta isMoving

    ; Check each direction
    lda pad1
    and #BTN_UP
    beq check_down  ; If not pressed, check next button
    lda #0          ; Direction for up
    sta direction
    lda #1          ; Indicate walking
    sta isMoving
    jsr move_player_up
    jmp end_update ; Skip further checks

    check_down:
    lda pad1
    and #BTN_DOWN
    beq check_left
    lda #1
    sta direction
    lda #1
    sta isMoving
    jsr move_player_down
    jmp end_update

    check_left:
    lda pad1
    and #BTN_LEFT
    beq check_right
    lda #2
    sta direction
    lda #1
    sta isMoving
    jsr move_player_left
    jmp end_update

    check_right:
    lda pad1
    and #BTN_RIGHT
    beq end_update
    lda #3
    sta direction
    lda #1
    jsr move_player_right
    sta isMoving


    end_update:
    lda direction
    cmp changed_direction ; Check if the direction has changed
    beq no_change_direction ; If the direction has not changed, skip changing the sprite
    lda direction 
    sta changed_direction ; Update changed_direction to the new direction
    jsr NOAnimated_sprite 
    no_change_direction:
    rts

NOAnimated_sprite:
  ; Get the offset for the sprite
  jsr get_offset_for_direction_sprite

    ldx #1 ; offset for buffer, where the tile data for tile 1 is stored
    ldy #0 ; offset for left_tank_tiles and 4 count
    reset_sprites_loop:
    tya ; Load y to a
    pha ; Push y to the stack

    ldy offset_static_sprite ; Load offset_static_sprite to x
    lda left_tank_tiles, y ; Load tile data for tile y
    sta sprite_buffer, x ; Store the tile data in the buffer
    
    lda offset_static_sprite ; Load offset_static_sprite to a
    clc
    adc #1
    sta offset_static_sprite ; Store the updated offset_static_sprite back to offset_static_spri
    pla
    tay
    ; ; pop in stack variables
    txa ; Load x to a
    clc
    adc #4 ; Add 4 to x to move to the next tile data
    tax ; Store the updated x back to x
    
    iny
    cpy #4 ; Check if y is 4
    bne reset_sprites_loop

  jmp end_update

get_offset_for_direction_sprite:
  ; i will traverse through left_tank_tiles to get the offset of the sprite
  LDA direction     
  CMP #3         ; Compare offset_static_sprite with 3
  BEQ SetValue3  
  CMP #2
  BEQ SetValue2  ; If offset_static_sprite is 2, branch to code that sets Y to the desired value for this case
  CMP #1
  BEQ SetValue1 

  ; If none of the above, we assume offset_static_sprite is 0 and fall through to SetValue0
  SetValue0:
      LDA #0         ; Set offset_static_sprite to the value corresponding to offset_static_sprite being 0
      STA offset_static_sprite
      JMP Continue   ; Jump to the rest of the code
  SetValue1:
      LDA #4       ; Set offset_static_sprite to the value corresponding to offset_static_sprite being 1
      STA offset_static_sprite
      JMP Continue
  SetValue2:
      LDA #8        ; Set offset_static_sprite to the value corresponding to offset_static_sprite being 2
      STA offset_static_sprite
      JMP Continue
  SetValue3:
      LDA #12         
      STA offset_static_sprite
      ; here
  Continue:
      rts

move_player_up:
    ldx #SPRITE_Y_BASE_ADDR
    ldy #0
    move_player_up_loop:
        lda sprite_buffer, x
        clc
        sbc #1
        sta sprite_buffer, x
        txa
        clc
        adc #4
        tax
        iny
        cpy #4
        bne move_player_up_loop
    rts

move_player_down:
    ldx #SPRITE_Y_BASE_ADDR
    ldy #0
    move_player_down_loop:
        lda sprite_buffer, x
        clc
        adc #2
        sta sprite_buffer, x
        txa
        clc
        adc #4
        tax
        iny
        cpy #4
        bne move_player_down_loop
    rts

move_player_left:
    ldx #SPRITE_X_BASE_ADDR
    ldy #0
    move_player_left_loop:
        lda sprite_buffer, x
        clc
        sbc #1
        sta sprite_buffer, x
        txa
        clc
        adc #4
        tax
        iny
        cpy #4
        bne move_player_left_loop
    rts

move_player_right:
    ldx #SPRITE_X_BASE_ADDR
    ldy #0
    move_player_right_loop:
        lda sprite_buffer, x
        clc
        adc #2
        sta sprite_buffer, x
        txa
        clc
        adc #4
        tax
        iny
        cpy #4
        bne move_player_right_loop
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


left_tank_tiles:
      ; 0   1     2   3     4   5     6    7   8     9   A   B     C    D     E   F
.byte $02, $03, $13, $12, $06, $07, $17, $16, $22, $23, $33, $32, $26, $27, $37, $36


; Character memory
.segment "CHARS"
.incbin "tanks.chr"