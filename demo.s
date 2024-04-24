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

; Nametable things
; These are used for nametable subroutines
NAMETABLE_PTR: .res 2
SELECTED_NAMETABLE: .res 2
SELECTED_ATTRIBUTES: .res 2
SELECTED_TILE_WRITE: .res 1
DECODED_BYTE_IDX: .res 1
BYTE_TO_DECODE: .res 1
BITS_FROM_BYTE: .res 1
SCROLL_POSITION_X: .res 1
SCROLL_POSITION_Y: .res 1
MEGATILES_PTR: .res 2
need_update_nametable: .res 1

; Gameplay things
CURRENT_STAGE: .res 1

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

load_nametable:
  ; Set stage to 1
  lda #1
  sta CURRENT_STAGE

  ; Select first nametable
  lda #<stage_one_left_packaged
  sta SELECTED_NAMETABLE
  lda #>stage_one_left_packaged
  sta SELECTED_NAMETABLE+1

  ; Select first attribute table
  lda #<stage_one_left_attributes
  sta SELECTED_ATTRIBUTES
  lda #>stage_one_left_attributes
  sta SELECTED_ATTRIBUTES+1

  ; $2000 for first nametable
  lda #$20
  sta NAMETABLE_PTR
  lda #$00
  sta NAMETABLE_PTR+1
  jsr write_nametable

  ; $23C0 for first attribute table
  lda #$23
  sta NAMETABLE_PTR
  lda #$C0
  sta NAMETABLE_PTR+1
  jsr load_attributes

  ; Select second nametable
  lda #<stage_one_right_packaged
  sta SELECTED_NAMETABLE
  lda #>stage_one_right_packaged
  sta SELECTED_NAMETABLE+1

  ; Select second attribute table
  lda #<stage_one_right_attributes
  sta SELECTED_ATTRIBUTES
  lda #>stage_one_right_attributes
  sta SELECTED_ATTRIBUTES+1

  ; $2400 for second nametable
  lda #$24
  sta NAMETABLE_PTR
  lda #$00
  sta NAMETABLE_PTR+1
  jsr write_nametable

  ; $27C0 for second attribute table
  lda #$27
  sta NAMETABLE_PTR
  lda #$C0
  sta NAMETABLE_PTR+1
  jsr load_attributes


enable_rendering:

; Set PPUSCROLL to 0,0
  lda #$00
  sta PPUSCROLL
  lda #$00
  sta PPUSCROLL

  lda #%10000000	; Enable NMI
  sta PPUCTRL
  lda #%00011110
  sta PPUMASK

forever:
  lda vblank_flag
  cmp #1
  bne not_sync
    jsr handle_input
    jsr handle_nametable_change
    jsr update_player
    jsr update_sprites
  not_sync:
      jmp forever



nmi:
    pha
    txa
    pha
    tya
    pha
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

  scroll_screen_check:
  ; TODO Stop at 255
  lda SCROLL_POSITION_X
  cmp #255
  beq skip_scroll_increment

  ; Increment PPUSCROLL to scroll the screen by 60 pxs/second 
  inc SCROLL_POSITION_X

  skip_scroll_increment:
  lda SCROLL_POSITION_X
  sta PPUSCROLL
  lda SCROLL_POSITION_Y
  sta PPUSCROLL

  ; Reset scroll position
  lda #$00
  sta PPUSCROLL
  lda #$00
  sta PPUSCROLL
  pla
  tay
  pla
  tax
  pla
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
; Loads, decodes and writes a nametable at NAME_TABLE_PTR 
; from a packaged nametable in ROM
write_nametable:

  ; Save registers to stack
  pha
  txa
  pha
  tya
  pha

  ; Based on CURRENT_STAGE, select the correct megatiles
  lda CURRENT_STAGE
  cmp #1
  ; If stage 1, load stage one megatiles
  beq get_cave_megatiles
  cmp #2
  beq get_netherrealm_tiles
  
  ;choose the correct megatiles
  get_cave_megatiles:
      ; Load the megatiles for the cave
      lda #<megatiles_stage_one
      ; Load the low byte of the address of the megatiles
      sta MEGATILES_PTR
      ; Load the high byte of the address of the megatiles
      lda #>megatiles_stage_one
      sta MEGATILES_PTR+1
      ; Jump to the dec_write_nmtable subroutine
      jmp dec_write_nmtable
  
  get_netherrealm_tiles:
      lda #<megatiles_stage_two
      sta MEGATILES_PTR
      lda #>megatiles_stage_two
      sta MEGATILES_PTR+1
      jmp dec_write_nmtable

  dec_write_nmtable:
  ldx #0
  read_nametable_loop:
      txa
      tay
      lda (SELECTED_NAMETABLE), y
      sta BYTE_TO_DECODE
      jsr decode_and_write_byte

      ; Check if x+1 % 4 == 0, means we read 4 bytes, increment NAMETABLE_PTR by 32
      txa
      clc
      adc #1
      and #%00000011
      beq increment_nametable_ptr
      jmp skip_increment_nametable_ptr

      increment_nametable_ptr:
          lda NAMETABLE_PTR+1
          clc
          adc #32
          sta NAMETABLE_PTR+1
      
          ; Check if carry, need to increment high byte
          bcc skip_increment_nametable_ptr
          inc NAMETABLE_PTR
      
      skip_increment_nametable_ptr:
          inx 
          cpx #60
          bne read_nametable_loop
  
  ; Done with subroutine, pop registers from stack
  pla
  tay
  pla
  tax
  pla

  rts
; Decodes a byte and writes the corresponding 2x2 region of the nametable
decode_and_write_byte:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ; Loop through 2-bit pairs of the byte
    ; Each 2-bit pair corresponds to the top left tile of a 2x2 megatile, 
    ; can be used to index megatile array
    ldx #0
    read_bits_loop:
        lda #$00
        ; we use this to read 2 bits at a time
        sta BITS_FROM_BYTE ; Clear BITS_FROM_BYTE
        
        lda BYTE_TO_DECODE ; Load byte to decode
        clc
        asl ; Shift to read 1 bit into carry
        rol BITS_FROM_BYTE ; Rotate carry into BITS_FROM_BYTE
        asl ; Shift to read 1 bit into carry
        rol BITS_FROM_BYTE ; Rotate carry into BITS_FROM_BYTE
        sta BYTE_TO_DECODE ; Save byte back to BYTE_TO_DECODE

        ldy BITS_FROM_BYTE ; Save the 2-bit pair to X register
        lda (MEGATILES_PTR), y ; Load tile from megatiles based on 2-bit pair
        sta SELECTED_TILE_WRITE ; Save selected tile to SELECTED_TILE_WRITE
        
        ; From SELECTED_TILE_WRITE, call write_region_2x2_nametable 
        ; subroutine to write 2x2 region of nametable
        ; based on the top left tile of the mega tile selected
        jsr write_2x2_region_nametable

        ; Move NAME_TABLE_PTR to next 2x2 region
        lda NAMETABLE_PTR+1
        clc
        adc #2
        sta NAMETABLE_PTR+1

        ; Increment x to move to next 2-bit pair
        inx
        cpx #4
        bne read_bits_loop
    
    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla

    rts
; Writes a 2x2 region of the nametable based on the top left tile
write_2x2_region_nametable:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ; Write first tile of 2x2 region
    lda NAMETABLE_PTR
    sta PPUADDR
    lda NAMETABLE_PTR+1
    sta PPUADDR
    lda SELECTED_TILE_WRITE
    sta PPUDATA

    ; Write second tile of 2x2 region
    lda NAMETABLE_PTR
    sta PPUADDR
    lda NAMETABLE_PTR+1
    clc
    adc #1
    sta PPUADDR
    lda SELECTED_TILE_WRITE
    clc
    adc #1
    sta PPUDATA

    ; Write third tile of 2x2 region
    lda NAMETABLE_PTR
    sta PPUADDR
    lda NAMETABLE_PTR+1
    clc
    adc #32
    sta PPUADDR
    lda SELECTED_TILE_WRITE
    clc
    adc #16
    sta PPUDATA

    ; Write fourth tile of 2x2 region
    lda NAMETABLE_PTR
    sta PPUADDR
    lda NAMETABLE_PTR+1
    clc
    adc #33
    sta PPUADDR
    lda SELECTED_TILE_WRITE
    clc
    adc #17
    sta PPUDATA

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla

    rts
; Writes attributes to NAME_TABLE_PTR from attributes in ROM
load_attributes:
  ; Save registers to stack
  pha
  txa
  pha
  tya
  pha

  ldx #0
  read_attribute_loop:
      txa
      tay
      lda (SELECTED_ATTRIBUTES), y
      sta PPUDATA
      inx
      cpx #64
      bne read_attribute_loop
  ; Done writing attributes

  ; Pop registers from stack
  pla
  tay
  pla
  tax
  pla

  rts
handle_nametable_change:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ; If A was not pressed, skip to end
    lda pad1
    and #BTN_A
    beq skip_nametable_change

    ; Disable disable NMI and screen
    lda PPUCTRL
    and #%01111111
    sta PPUCTRL
    lda PPUMASK
    and #%11100000
    sta PPUMASK

    vblankwait3:
        bit PPUSTATUS
        bpl vblankwait3


    ; If in stage one, set to stage two
    ; If in stage two, set to stage one
    lda CURRENT_STAGE
    cmp #1
    beq set_stage_two
    cmp #2
    beq set_stage_one

    set_stage_two:
        lda #1
        sta need_update_nametable
        lda #2
        sta CURRENT_STAGE
        jmp call_update_nametable
    
    set_stage_one:
        lda #1
        sta need_update_nametable
        lda #1
        sta CURRENT_STAGE
        jmp call_update_nametable
    
    call_update_nametable:
        ; Set scroll position to 0,0
        lda #$00
        sta SCROLL_POSITION_X
        sta SCROLL_POSITION_Y
        jsr update_nametable

    skip_nametable_change:

    ; Restore NMI and screen
    lda #$80
    sta PPUCTRL
    lda #$1e
    sta PPUMASK

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla
    
    rts

update_nametable:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ; Check if need_update_nametable is set
    lda need_update_nametable
    cmp #1
    bne skip_update_nametable_intermediate

    ; Select nametable based on CURRENT_STAGE
    lda CURRENT_STAGE
    cmp #1
    beq select_stage_one

    lda CURRENT_STAGE
    cmp #2
    beq select_stage_two

    select_stage_one:
        ; Load stage one left nametables
        lda #<stage_one_left_packaged
        sta SELECTED_NAMETABLE
        lda #>stage_one_left_packaged
        sta SELECTED_NAMETABLE+1

        lda #$20
        sta NAMETABLE_PTR
        lda #$00
        sta NAMETABLE_PTR+1
        jsr write_nametable

        ; Load stage one left attributes
        lda #<stage_one_left_attributes
        sta SELECTED_ATTRIBUTES
        lda #>stage_one_left_attributes
        sta SELECTED_ATTRIBUTES+1

        lda #$23
        sta NAMETABLE_PTR
        lda #$C0
        sta NAMETABLE_PTR+1
        jsr load_attributes

        ; Load stage one right nametables
        lda #<stage_one_right_packaged
        sta SELECTED_NAMETABLE
        lda #>stage_one_right_packaged
        sta SELECTED_NAMETABLE+1

        lda #$24
        sta NAMETABLE_PTR
        lda #$00
        sta NAMETABLE_PTR+1
        jsr write_nametable

        ; Load stage one right attributes
        lda #<stage_one_right_attributes
        sta SELECTED_ATTRIBUTES
        lda #>stage_one_right_attributes
        sta SELECTED_ATTRIBUTES+1

        lda #$27
        sta NAMETABLE_PTR
        lda #$C0
        sta NAMETABLE_PTR+1
        jsr load_attributes

        jmp skip_update_nametable


    skip_update_nametable_intermediate:
        jmp skip_update_nametable
    
    select_stage_two:
        ; Load stage two left nametables
        lda #<stage_two_left_packaged
        sta SELECTED_NAMETABLE
        lda #>stage_two_left_packaged
        sta SELECTED_NAMETABLE+1

        lda #$20
        sta NAMETABLE_PTR
        lda #$00
        sta NAMETABLE_PTR+1
        jsr write_nametable

        ; Load stage two left attributes
        lda #<stage_two_left_attributes
        sta SELECTED_ATTRIBUTES
        lda #>stage_two_left_attributes
        sta SELECTED_ATTRIBUTES+1

        lda #$23
        sta NAMETABLE_PTR
        lda #$C0
        sta NAMETABLE_PTR+1
        jsr load_attributes

        ; Load stage two right nametables
        lda #<stage_two_right_packaged
        sta SELECTED_NAMETABLE
        lda #>stage_two_right_packaged
        sta SELECTED_NAMETABLE+1

        lda #$24
        sta NAMETABLE_PTR
        lda #$00
        sta NAMETABLE_PTR+1
        jsr write_nametable

        ; Load stage two right attributes
        lda #<stage_two_right_attributes
        sta SELECTED_ATTRIBUTES
        lda #>stage_two_right_attributes
        sta SELECTED_ATTRIBUTES+1

        lda #$27
        sta NAMETABLE_PTR
        lda #$C0
        sta NAMETABLE_PTR+1
        jsr load_attributes

        jmp skip_update_nametable

    skip_update_nametable:
    ; Set need_update_nametable to 0
    lda #0
    sta need_update_nametable

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla
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
.byte $00, $20,$15,$06 ;
.byte $0F, $21,$00,$10 
.byte $00, $01, $12, $10 
.byte $00, 15,06,10

; sprite palette
.byte $0F, $1C, $2C, $1A
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00

sprites:
.byte $00, $02, $00, $00
.byte $00, $03, $00, $08
.byte $08, $12, $00, $00
.byte $08, $13, $00, $08

; Megatiles
megatiles_stage_one:
.byte $08, $04, $06, $02 
megatiles_stage_two:
.byte $08, $02, $04, $06

left_tank_tiles:
      ; 0   1     2   3     4   5     6    7   8     9   A   B     C    D     E   F
.byte $02, $03, $13, $12, $06, $07, $17, $16, $22, $23, $33, $32, $26, $27, $37, $36

; Stage one nametables and attributes
stage_one_left_packaged:
.incbin "stage_one_left_packaged.bin"
stage_one_left_attributes:
.incbin "stage_one_left_attributes.bin"
stage_one_right_packaged:
.incbin "stage_one_right_packaged.bin"
stage_one_right_attributes:
.incbin "stage_one_right_attributes.bin"

; Stage two nametables and attributes
stage_two_left_packaged:
.incbin "stage_two_left_packaged.bin"
stage_two_left_attributes:
.incbin "stage_two_left_attributes.bin"
stage_two_right_packaged:
.incbin "stage_two_right_packaged.bin"
stage_two_right_attributes:
.incbin "stage_two_right_attributes.bin"

cave_tiles:
; spiderweb, diamond brick, brick, empty
.byte $03, $04, $06, $00
; Character memory
.segment "CHARS"
.incbin "Cave.chr"
