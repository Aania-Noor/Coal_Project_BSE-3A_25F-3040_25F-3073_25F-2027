org 100h
; NAMED CONSTANTS (EQU) - Screen, Tiles, Colors, Keys and Limits
; Screen & Buffer Limits
SCREEN_W        EQU 320
SCREEN_H        EQU 200
SCREEN_WORDS    EQU 32000
VGA_SEG         EQU 0A000h
BUF_PARAGRAPHS  EQU 1000h

; Tile & Level Map Limits
TILE_SIZE       EQU 16
MAP_COLS        EQU 60
MAP_ROWS        EQU 12
MAP_TILES       EQU 720
LEVEL_W         EQU 960
LEVEL_H         EQU 192
MAX_CAM_X       EQU 640
VIEW_COLS       EQU 21

; VGA Mode 13h Palette Colours
COL_BLACK       EQU 0
COL_GREEN       EQU 2
COL_RED         EQU 4
COL_BROWN       EQU 6
COL_DGRAY       EQU 8
COL_LGREEN      EQU 10
COL_LRED        EQU 12
COL_YELLOW      EQU 14
COL_WHITE       EQU 15
COL_ORANGE      EQU 42
COL_SKY         EQU 53

; Keyboard Scan Codes (INT 09h)
KEY_ESC         EQU 01h
KEY_ENTER       EQU 1Ch
KEY_LSHIFT      EQU 2Ah
KEY_P           EQU 19h
KEY_SPACE       EQU 39h
KEY_UP          EQU 48h
KEY_LEFT        EQU 4Bh
KEY_RIGHT       EQU 4Dh
KEY_DOWN        EQU 50h

; Game States & Gameplay Limits
ST_TITLE        EQU 0
ST_PLAYING      EQU 1
ST_PAUSED       EQU 2
ST_DYING        EQU 3
ST_LIFELOST     EQU 4
ST_WINSEQ       EQU 5
ST_COMPLETE     EQU 6
ST_GAMEOVER     EQU 7
ST_EXIT         EQU 8

MAX_ENEMIES     EQU 8
START_LIVES     EQU 3
MAX_LIVES       EQU 99
START_TIME      EQU 300
TICKS_PER_SEC   EQU 36
MAX_COINS       EQU 100
; Entry point: allocate off screen buffer memory.
Start:
    cld
    mov ah, 4Ah
    mov bx, BUF_PARAGRAPHS
    int 21h
    mov ah, 48h
    mov bx, BUF_PARAGRAPHS
    int 21h
    jc near Use_Next_Seg
    mov [Buffer_Seg], ax
    jmp Init_Game
	; Fallback if DOS allocation fails: use next 64 KB segment.
Use_Next_Seg:
    mov ax, cs
    add ax, BUF_PARAGRAPHS
    mov [Buffer_Seg], ax
	; Hook interrupts, switch to VGA Mode 13h, and enter title state.
Init_Game:
    call Hook_Ints
    mov ax, 0013h
    int 10h
    mov byte [Game_State], ST_TITLE
    mov byte [Menu_Choice], 0
	; Main game loop executed once per timer tick.
Main_Loop:
    mov al, [Tick_Flag]
	; Wait until the timer interrupt increments the tick flag.
Wait_Tick:
    cmp al, [Tick_Flag]
    je near Wait_Tick
    xor bx, bx
    mov bl, [Game_State]
    cmp bl, ST_EXIT
    jne near Check_St_Title
    jmp Exit_Dos
	; Check if the game is currently in the title state.
Check_St_Title:
    cmp bl, ST_TITLE
    jne near Check_St_Play
    jmp State_Title
	; Check if the game is currently in the playing state.
Check_St_Play:
    cmp bl, ST_PLAYING
    jne near Check_St_Pause
    jmp State_Playing
	; Check if the game is currently paused.
Check_St_Pause:
    cmp bl, ST_PAUSED
    jne near Check_St_Die
    jmp State_Paused
	; Check if Mario is in the dying animation state.
Check_St_Die:
    cmp bl, ST_DYING
    jne near Check_St_Life
    jmp State_Dying
	; Check if the life lost screen should be shown.
Check_St_Life:
    cmp bl, ST_LIFELOST
    jne near Check_St_Win
    jmp State_Lifelost
	; Check if the flagpole win sequence is active.
Check_St_Win:
    cmp bl, ST_WINSEQ
    jne near Check_St_Comp
    jmp State_Winseq
	; Check if the level complete screen should be shown.
Check_St_Comp:
    cmp bl, ST_COMPLETE
    jne near Check_St_Over
    jmp State_Complete
	; Check if the game over screen should be shown.
Check_St_Over:
    cmp bl, ST_GAMEOVER
    jne near Main_Loop
    jmp State_Gameover
; Interrupts (INT 09h Keyboard & INT 08h Timer)
Hook_Ints:
    push ax
    push bx
    push dx
    push es
    mov ax, 3509h
    int 21h
    mov [Old_Int09_Off], bx
    mov [Old_Int09_Seg], es
    mov ax, 2509h
    mov dx, Key_Handler
    int 21h
    mov ax, 3508h
    int 21h
    mov [Old_Int08_Off], bx
    mov [Old_Int08_Seg], es
    mov ax, 2508h
    mov dx, Timer_Handler
    int 21h
    cli
    mov al, 36h
    out 43h, al
    mov al, 00h
    out 40h, al
    mov al, 80h
    out 40h, al
    sti
    pop es
    pop dx
    pop bx
    pop ax
    ret
	; Restore original BIOS timer rate and interrupt vectors before exit.
Unhook_Ints:
    push ax
    push dx
    push ds
    cli
    mov al, 36h
    out 43h, al
    xor al, al
    out 40h, al
    out 40h, al
    sti
    mov dx, [Old_Int08_Off]
    mov ds, [Old_Int08_Seg]
    mov ax, 2508h
    int 21h
    mov dx, [cs:Old_Int09_Off]
    mov ds, [cs:Old_Int09_Seg]
    mov ax, 2509h
    int 21h
    pop ds
    pop dx
    pop ax
    ret
	; Custom INT 09h handler to track key presses and releases.
Key_Handler:
    push ax
    push bx
    push ds
    mov ax, cs
    mov ds, ax
    in al, 60h
    cmp al, 0E0h
    je near Key_Eoi
    mov bl, al
    and bl, 7Fh
    xor bh, bh
    test al, 80h
    jnz near Key_Up_Event
    mov byte [Key_Table + bx], 1
    jmp Key_Eoi
	; Mark key as released (0) in the key state table.
Key_Up_Event:
    mov byte [Key_Table + bx], 0
	
Key_Eoi:
    mov al, 20h
    out 20h, al
    pop ds
    pop bx
    pop ax
    iret
	; Custom INT 08h handler to drive game ticks and chain to BIOS.
Timer_Handler:
    push ax
    push ds
    mov ax, cs
    mov ds, ax
    inc byte [Tick_Flag]
    inc byte [Pit_Div]
    test byte [Pit_Div], 1
    jnz near Skip_Old_Timer
    pop ds
    pop ax
    jmp far [cs:Old_Int08_Off]
	; Send EOI manually on odd ticks without calling the BIOS timer.
Skip_Old_Timer:
    mov al, 20h
    out 20h, al
    pop ds
    pop ax
    iret
; GAME STATES
State_Title:
    mov bl, KEY_UP
    xor bh, bh
    cmp byte [Key_Table + bx], 1
    jne near Title_Chk_Down
    mov byte [Menu_Choice], 0
	; Move menu selector arrow down to EXIT.
Title_Chk_Down:
    mov bl, KEY_DOWN
    xor bh, bh
    cmp byte [Key_Table + bx], 1
    jne near Title_Chk_Esc
    mov byte [Menu_Choice], 1
	; Exit immediately if Esc is pressed on the title screen.
Title_Chk_Esc:
    mov bl, KEY_ESC
    xor bh, bh
    cmp byte [Key_Table + bx], 1
    jne near Title_Chk_Enter
    mov byte [Key_Table + bx], 0
    mov byte [Game_State], ST_EXIT
    jmp Main_Loop
Title_Chk_Enter:
    mov bl, KEY_ENTER
    xor bh, bh
    cmp byte [Key_Table + bx], 1
    jne near Draw_Title
    mov byte [Key_Table + bx], 0
    cmp byte [Menu_Choice], 0
    jne near Title_Exit_Pick
    call New_Game
    mov byte [Game_State], ST_PLAYING
    jmp Main_Loop
	; Switch game state to exit when EXIT is selected.
Title_Exit_Pick:
    mov byte [Game_State], ST_EXIT
    jmp Main_Loop
	; Render the title screen background, logo box, menu options, and sprites.
Draw_Title:
    push COL_SKY
    call Clear_Buffer
    ; Ground
    push 0
    push 176
    push SCREEN_W
    push 24
    push COL_BROWN
    call Fill_Rect
    push 0
    push 172
    push SCREEN_W
    push 4
    push COL_GREEN
    call Fill_Rect
    ; Decorative clouds on Title Screen
    push 40
    push 24
    call Draw_Cloud
    push 220
    push 32
    call Draw_Cloud
    ; Title Box
    push 44
    push 22
    push 232
    push 44
    push COL_RED
    call Fill_Rect
    push 46
    push 24
    push 228
    push 40
    push COL_BLACK
    call Fill_Rect
    push 76
    push 32
    push COL_YELLOW
    push Str_Title1
    call Draw_String
    push 136
    push 48
    push COL_WHITE
    push Str_Title2
    call Draw_String
    ; Menu Box
    push 92
    push 84
    push 136
    push 52
    push COL_WHITE
    call Fill_Rect
    push 94
    push 86
    push 132
    push 48
    push COL_BLACK
    call Fill_Rect
    push 120
    push 96
    push COL_YELLOW
    push Str_Start
    call Draw_String
    push 120
    push 116
    push COL_WHITE
    push Str_Exit
    call Draw_String
    ; Selector Arrow
    mov ax, 96
    cmp byte [Menu_Choice], 0
    je near Draw_Title_Arrow
    mov ax, 116
Draw_Title_Arrow:
    push 106
    push ax
    push COL_LRED
    push 62
    call Draw_Char
    push 68
    push 156
    push COL_WHITE
    push Str_Credits
    call Draw_String
    ; Mario & Goomba preview
    push 48
    push 156
    push Spr_Mario_Small
    push 0
    call Draw_Sprite
    push 256
    push 156
    push Spr_Goomba
    push 0
    call Draw_Sprite
    call Flip_Buffer
    jmp Main_Loop
	; Handle active gameplay state: check pause exit keys and run frame updates
State_Playing:
    mov bl, KEY_P
    xor bh, bh
    cmp byte [Key_Table + bx], 1
    jne near Play_Chk_Esc
    mov byte [Key_Table + bx], 0
    mov byte [Game_State], ST_PAUSED
    jmp Main_Loop
Play_Chk_Esc:
    mov bl, KEY_ESC
    xor bh, bh
    cmp byte [Key_Table + bx], 1
    jne near Play_Step
    mov byte [Key_Table + bx], 0
    mov byte [Game_State], ST_TITLE
    jmp Main_Loop
	; Update Mario, enemies, mushroom, collisions, and score popups
Play_Step:
    call Update_Mario
    call Update_Enemies
    call Update_Mushroom
    call Check_Entities
    call Update_Popup
    cmp byte [Mario_Invuln], 0
    je near Play_Clock
    dec byte [Mario_Invuln]
Play_Clock:
    inc byte [Sec_Ticks]
    cmp byte [Sec_Ticks], TICKS_PER_SEC
    jb near Play_Pit_Chk
    mov byte [Sec_Ticks], 0
    cmp word [Game_Time], 0
    je near Play_Time_Zero
    dec word [Game_Time]
    cmp word [Game_Time], 0
    jne near Play_Pit_Chk
	; Trigger death if the level timer reaches zero.
Play_Time_Zero:
    mov byte [Death_Pit], 0
    call Trigger_Death
    jmp Main_Loop
Play_Pit_Chk:
    mov ax, [Mario_Y]
    cmp ax, LEVEL_H
    jl near Play_Win_Chk
    mov byte [Death_Pit], 1
    call Trigger_Death
    jmp Main_Loop
Play_Win_Chk:
    cmp byte [Level_Won], 1
    jne near Play_Cam
    mov byte [Game_State], ST_WINSEQ
    mov byte [Seq_Timer], TICKS_PER_SEC
    jmp Main_Loop
	; Update the scrolling camera and render the current gameplay frame.
Play_Cam:
    call Update_Camera
    call Render_Scene
    call Flip_Buffer
    jmp Main_Loop
State_Paused:
    mov bl, KEY_P
    xor bh, bh
    cmp byte [Key_Table + bx], 1
    jne near Pause_Chk_Esc
    mov byte [Key_Table + bx], 0
    mov byte [Game_State], ST_PLAYING
    jmp Main_Loop
Pause_Chk_Esc:
    mov bl, KEY_ESC
    xor bh, bh
    cmp byte [Key_Table + bx], 1
    jne near Draw_Pause
    mov byte [Key_Table + bx], 0
    mov byte [Game_State], ST_TITLE
    jmp Main_Loop
	; Draw the frozen gameplay scene with the PAUSED overlay box.
Draw_Pause:
    call Render_Scene
    push 88
    push 76
    push 144
    push 48
    push COL_WHITE
    call Fill_Rect
    push 90
    push 78
    push 140
    push 44
    push COL_BLACK
    call Fill_Rect
    push 136
    push 88
    push COL_YELLOW
    push Str_Paused
    call Draw_String
    push 100
    push 104
    push COL_WHITE
    push Str_Resume
    call Draw_String
    call Flip_Buffer
    jmp Main_Loop
	; Animate Marios death hop and fall before decrementing lives
State_Dying:
    mov ax, [Mario_Vy]
    add ax, 64
    mov [Mario_Vy], ax
    xor bx, bx
    mov bl, [Mario_Y_Sub]
    add bx, ax
    mov [Mario_Y_Sub], bl
    mov al, bh
    cbw
    add [Mario_Y], ax
    call Render_Scene
    call Flip_Buffer
    dec byte [Seq_Timer]
    jnz near Main_Loop
    dec byte [Lives]
    cmp byte [Lives], 0
    jle near Die_To_Over
    mov byte [Game_State], ST_LIFELOST
    mov byte [Seq_Timer], 72
    jmp Main_Loop
Die_To_Over:
    mov byte [Game_State], ST_GAMEOVER
    jmp Main_Loop
	; Display the World 1-1 lives-left screen for two seconds before restarting.
State_Lifelost:
    push COL_BLACK
    call Clear_Buffer
    push 124
    push 60
    push COL_WHITE
    push Str_World
    call Draw_String
    push 112
    push 92
    push Spr_Mario_Small
    push 0
    call Draw_Sprite
    push 140
    push 96
    push COL_WHITE
    push 120
    call Draw_Char
    xor ax, ax
    mov al, [Lives]
    push 160
    push 96
    push COL_WHITE
    push ax
    push 1
    call Draw_Number
    push 120
    push 136
    push COL_YELLOW
    push Str_Lifelost
    call Draw_String
    call Flip_Buffer
    dec byte [Seq_Timer]
    jnz near Main_Loop
    call Reset_Level
    mov byte [Game_State], ST_PLAYING
    jmp Main_Loop
State_Winseq:
    call Update_Popup
    mov bx, 128
    cmp byte [Mario_Hp], 1
    jne near Win_Slide_Chk
    mov bx, 144
Win_Slide_Chk:
    mov ax, [Mario_Y]
    cmp ax, bx
    jge near Win_Walk_Castle
    add word [Mario_Y], 2
    jmp Win_Render
	; Walk Mario toward the castle door and calculate the remaining time bonus.
Win_Walk_Castle:
    inc word [Mario_X]
    dec byte [Seq_Timer]
    jnz near Win_Render
    mov ax, [Game_Time]
    mov bx, 50
    mul bx
    mov [Time_Bonus], ax
    push dx
    push ax
    call Add_Score32
    mov byte [Game_State], ST_COMPLETE
    jmp Main_Loop
Win_Render:
    call Render_Scene
    call Flip_Buffer
    jmp Main_Loop
State_Complete:
    mov bl, KEY_ENTER
    xor bh, bh
    cmp byte [Key_Table + bx], 1
    jne near Draw_Complete
    mov byte [Key_Table + bx], 0
    mov byte [Game_State], ST_TITLE
    jmp Main_Loop
	; Render the Level Complete summary screen with score, coins, and time bonus.
Draw_Complete:
    push COL_BLACK
    call Clear_Buffer
    push 24
    push 16
    push 272
    push 168
    push COL_YELLOW
    call Fill_Rect
    push 26
    push 18
    push 268
    push 164
    push COL_BLACK
    call Fill_Rect
    push 104
    push 32
    push COL_YELLOW
    push Str_Complete
    call Draw_String
    push 64
    push 64
    push COL_WHITE
    push Str_Lbl_Score
    call Draw_String
    push 176
    push 64
    push COL_WHITE
    call Draw_Score6
    push 64
    push 84
    push COL_WHITE
    push Str_Lbl_Coins
    call Draw_String
    xor ax, ax
    mov al, [Coins]
    push 176
    push 84
    push COL_WHITE
    push ax
    push 2
    call Draw_Number
    push 64
    push 104
    push COL_WHITE
    push Str_Lbl_Bonus
    call Draw_String
    push 176
    push 104
    push COL_YELLOW
    push word [Time_Bonus]
    push 4
    call Draw_Number
    push 68
    push 150
    push COL_LGREEN
    push Str_Enter_Cont
    call Draw_String
    call Flip_Buffer
    jmp Main_Loop
State_Gameover:
    mov bl, KEY_ENTER
    xor bh, bh
    cmp byte [Key_Table + bx], 1
    jne near Draw_Gameover
    mov byte [Key_Table + bx], 0
    mov byte [Game_State], ST_TITLE
    jmp Main_Loop
	; Wait for Enter on the Game Over screen to return to the title.
Draw_Gameover:
    push COL_BLACK
    call Clear_Buffer
    push 24
    push 24
    push 272
    push 152
    push COL_RED
    call Fill_Rect
    push 26
    push 26
    push 268
    push 148
    push COL_BLACK
    call Fill_Rect
    push 124
    push 52
    push COL_LRED
    push Str_Gameover
    call Draw_String
    push 80
    push 92
    push COL_WHITE
    push Str_Final_Sc
    call Draw_String
    push 188
    push 92
    push COL_YELLOW
    call Draw_Score6
    push 68
    push 144
    push COL_LGREEN
    push Str_Enter_Cont
    call Draw_String
    call Flip_Buffer
    jmp Main_Loop
	; Restore original interrupt vectors, return to text mode, and exit to DOS.
Exit_Dos:
    call Unhook_Ints
    mov ax, 0003h
    int 10h
    mov ax, 4C00h
    int 21h
; Game reset, popups and Scoring
New_Game:
    mov byte [Lives], START_LIVES
    mov word [Score_Lo], 0
    mov word [Score_Hi], 0
    mov byte [Coins], 0
    call Reset_Level
    ret
	; Reset Mario, camera, timer, map tiles, and enemy states to initial values.
Reset_Level:
    mov word [Mario_X], 32
    mov byte [Mario_X_Sub], 0
    mov word [Mario_Y], 144
    mov byte [Mario_Y_Sub], 0
    mov word [Mario_Vx], 0
    mov word [Mario_Vy], 0
    mov byte [Mario_On_Gnd], 1
    mov byte [Mario_Facing], 0
    mov byte [Mario_Hp], 1
    mov byte [Mario_Invuln], 0
    mov byte [Stomp_Chain], 0
    mov word [Camera_X], 0
    mov word [Game_Time], START_TIME
    mov byte [Sec_Ticks], 0
    mov byte [Level_Won], 0
    mov byte [Mush_Active], 0
    mov byte [Popup_Timer], 0
    push ds
    push es
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov si, Map_Original
    mov di, Map_Working
    mov cx, MAP_TILES
    rep movsb
    mov si, Enemy_Init
    mov di, Enemy_Table
    mov cx, 64
    rep movsb
    pop es
    pop ds
    ret
	; Reset Mario, camera, timer, map tiles, and enemy states to initial values.
Spawn_Popup:
    push ax
    mov [Popup_Val], ax
    mov ax, [Mario_X]
    mov [Popup_X], ax
    mov ax, [Mario_Y]
    sub ax, 10
    cmp ax, 18
    jge near Pop_Y_Ok
    mov ax, 18
	; Clamp popup Y coordinate so it never overlaps the top HUD bar.
Pop_Y_Ok:
    mov [Popup_Y], ax
    mov byte [Popup_Timer], TICKS_PER_SEC
    pop ax
    ret
Spawn_Popup_At:
    push ax
    mov [Popup_Val], ax
    mov [Popup_X], bx
    sub dx, 10
    cmp dx, 18
    jge near PopAt_Y_Ok
    mov dx, 18
	; Clamp custom popup Y coordinate below the HUD strip.
PopAt_Y_Ok:
    mov [Popup_Y], dx
    mov byte [Popup_Timer], TICKS_PER_SEC
    pop ax
    ret
Update_Popup:
    cmp byte [Popup_Timer], 0
    je near Upd_Pop_Done
    dec byte [Popup_Timer]
    test byte [Popup_Timer], 1
    jnz near Upd_Pop_Done
    cmp word [Popup_Y], 18
    jle near Upd_Pop_Done
    dec word [Popup_Y]
	; Exit popup update when no popup is currently active.
Upd_Pop_Done:
    ret
	; Draw the active floating score popup (+points) on screen.
Draw_Popup:
    cmp byte [Popup_Timer], 0
    je near Draw_Pop_Done
    mov ax, [Popup_X]
    sub ax, [Camera_X]
    cmp ax, 0
    jl near Draw_Pop_Done
    cmp ax, 280
    jg near Draw_Pop_Done
    push ax
    push word [Popup_Y]
    push COL_YELLOW
    push 43
    call Draw_Char
    add ax, 8
    mov bx, [Popup_Val]
    mov cx, 3
    cmp bx, 100
    jae near Pop_Chk_4Dig
    mov cx, 2
    jmp Pop_Draw_Num
	; Check if the popup value has four digits before drawing.
Pop_Chk_4Dig:
    cmp bx, 1000
    jb near Pop_Draw_Num
    mov cx, 4
Pop_Draw_Num:
    push ax
    push word [Popup_Y]
    push COL_YELLOW
    push bx
    push cx
    call Draw_Number
Draw_Pop_Done:
    ret
	; Add a 32 bit point value to the players score using ADD ADC.
Add_Score32:
    push bp
    mov bp, sp
    push ax
    push dx
    mov ax, [bp+4]
    mov dx, [bp+6]
    add [Score_Lo], ax
    adc [Score_Hi], dx
    cmp word [Score_Hi], 000Fh
    jb near Score_Ok
    ja near Score_Clamp
    cmp word [Score_Lo], 423Fh
    jbe near Score_Ok
Score_Clamp:
    mov word [Score_Hi], 000Fh
    mov word [Score_Lo], 423Fh
Score_Ok:
    pop dx
    pop ax
    pop bp
    ret 4
	; Increment coin counter and award an extra life at 100 coins.
Add_Coin:
    inc byte [Coins]
    cmp byte [Coins], MAX_COINS
    jb near Coin_Done
    mov byte [Coins], 0
    cmp byte [Lives], MAX_LIVES
    jae near Coin_Done
    inc byte [Lives]
Coin_Done:
    ret
	; Switch to the dying state and apply an upward hop unless Mario fell in a pit.
Trigger_Death:
    mov byte [Game_State], ST_DYING
    mov byte [Seq_Timer], 54
    cmp byte [Death_Pit], 1
    je near Death_No_Hop
    mov word [Mario_Vy], -1152
    ret
Death_No_Hop:
    mov word [Mario_Vy], 0
    ret
; Mario Physics & Title Collision 
Update_Mario:
    mov cx, 0240h
    mov bl, KEY_LSHIFT
    xor bh, bh
    cmp byte [Key_Table + bx], 1
    jne near Check_Left_Btn
    mov cx, 0380h
	; Accelerate Mario to the left and clamp to the negative speed limit.
Check_Left_Btn:
    xor dx, dx
    mov bl, KEY_LEFT
    xor bh, bh
    cmp byte [Key_Table + bx], 1
    jne near Check_Right_Btn
    mov dx, 1
    mov byte [Mario_Facing], 1
    sub word [Mario_Vx], 0038h
    neg cx
    cmp [Mario_Vx], cx
    jge near Check_Right_Btn
    mov [Mario_Vx], cx
    neg cx
	; Accelerate Mario to the right and clamp to the positive speed limit.
Check_Right_Btn:
    mov bl, KEY_RIGHT
    xor bh, bh
    cmp byte [Key_Table + bx], 1
    jne near Do_Friction
    mov dx, 1
    mov byte [Mario_Facing], 0
    add word [Mario_Vx], 0038h
    cmp [Mario_Vx], cx
    jle near Do_Friction
    mov [Mario_Vx], cx
Do_Friction:
    cmp dx, 1
    je near Check_Space_Btn
    cmp word [Mario_Vx], 0
    je near Check_Space_Btn
    jg near Fric_Right
    add word [Mario_Vx], 0048h
    cmp word [Mario_Vx], 0
    jle near Check_Space_Btn
    mov word [Mario_Vx], 0
    jmp Check_Space_Btn
	; Decelerate rightward velocity toward zero.
Fric_Right:
    sub word [Mario_Vx], 0048h
    cmp word [Mario_Vx], 0
    jge near Check_Space_Btn
    mov word [Mario_Vx], 0
Check_Space_Btn:
    mov bl, KEY_SPACE
    xor bh, bh
    cmp byte [Key_Table + bx], 1
    jne near Cut_Jump
    cmp byte [Mario_On_Gnd], 1
    jne near Do_Gravity
    mov word [Mario_Vy], -1960
    mov byte [Mario_On_Gnd], 0
    jmp Do_Gravity
Cut_Jump:
    cmp word [Mario_Vy], -512
    jge near Do_Gravity
    mov word [Mario_Vy], -512
Do_Gravity:
    add word [Mario_Vy], 0058h
    cmp word [Mario_Vy], 0500h
    jle near Step_X
    mov word [Mario_Vy], 0500h
	; Move Mario horizontally using 8.8 fixed-point arithmetic and clamp to screen edges.
Step_X:
    mov ax, [Mario_Vx]
    xor bx, bx
    mov bl, [Mario_X_Sub]
    add bx, ax
    mov [Mario_X_Sub], bl
    mov al, bh
    cbw
    add [Mario_X], ax
    mov ax, [Camera_X]
    cmp [Mario_X], ax
    jge near Clamp_Right_Wall
    mov [Mario_X], ax
    mov byte [Mario_X_Sub], 0
    mov word [Mario_Vx], 0
	;Prevent Mario from walking past the right end of the level
Clamp_Right_Wall:
    cmp word [Mario_X], 944
    jle near Check_Horiz_Tiles
    mov word [Mario_X], 944
    mov word [Mario_Vx], 0
Check_Horiz_Tiles:
    cmp word [Mario_Vx], 0
    je near Step_Y
    jl near Check_Left_Wall
    ; Right wall check: Head (Y+2), Waist (Y+16 if Super), Foot (Y+14 or Y+30)
    mov ax, [Mario_X]
    add ax, 13
    mov bx, [Mario_Y]
    add bx, 2
    call Test_Solid_At
    cmp al, 1
    je near Hit_Right_Wall
    cmp byte [Mario_Hp], 2
    jne near Test_R_Foot_Small
    mov ax, [Mario_X]
    add ax, 13
    mov bx, [Mario_Y]
    add bx, 16
    call Test_Solid_At
    cmp al, 1
    je near Hit_Right_Wall
    mov ax, [Mario_X]
    add ax, 13
    mov bx, [Mario_Y]
    add bx, 30
    call Test_Solid_At
    cmp al, 1
    je near Hit_Right_Wall
    jmp Step_Y
	; Check foot-level right wall collision for Small Mario.
Test_R_Foot_Small:
    mov ax, [Mario_X]
    add ax, 13
    mov bx, [Mario_Y]
    add bx, 14
    call Test_Solid_At
    cmp al, 1
    jne near Step_Y
Hit_Right_Wall:
    mov ax, [Mario_X]
    add ax, 13
    and ax, 0FFF0h
    sub ax, 14
    mov [Mario_X], ax
    mov word [Mario_Vx], 0
    jmp Step_Y
Check_Left_Wall:
    ; Left wall check: Head (Y+2), Waist (Y+16 if Super), Foot (Y+14 or Y+30)
    mov ax, [Mario_X]
    add ax, 2
    mov bx, [Mario_Y]
    add bx, 2
    call Test_Solid_At
    cmp al, 1
    je near Hit_Left_Wall
    cmp byte [Mario_Hp], 2
    jne near Test_L_Foot_Small
    mov ax, [Mario_X]
    add ax, 2
    mov bx, [Mario_Y]
    add bx, 16
    call Test_Solid_At
    cmp al, 1
    je near Hit_Left_Wall
    mov ax, [Mario_X]
    add ax, 2
    mov bx, [Mario_Y]
    add bx, 30
    call Test_Solid_At
    cmp al, 1
    je near Hit_Left_Wall
    jmp Step_Y
Test_L_Foot_Small:
    mov ax, [Mario_X]
    add ax, 2
    mov bx, [Mario_Y]
    add bx, 14
    call Test_Solid_At
    cmp al, 1
    jne near Step_Y
	; Snap Mario flush against a solid wall on his left and stop horizontal speed.
Hit_Left_Wall:
    mov ax, [Mario_X]
    add ax, 2
    and ax, 0FFF0h
    add ax, 14
    mov [Mario_X], ax
    mov word [Mario_Vx], 0
Step_Y:
    mov ax, [Mario_Vy]
    xor bx, bx
    mov bl, [Mario_Y_Sub]
    add bx, ax
    mov [Mario_Y_Sub], bl
    mov al, bh
    cbw
    add [Mario_Y], ax
    cmp word [Mario_Vy], 0
    jl near Check_Head_Hit
    mov dx, TILE_SIZE
    cmp byte [Mario_Hp], 2
    jne near Check_Feet_Tiles
    mov dx, 32
Check_Feet_Tiles:
    mov ax, [Mario_X]
    add ax, 3
    mov bx, [Mario_Y]
    add bx, dx
    call Test_Solid_At
    cmp al, 1
    je near Landed_On_Tile
    mov ax, [Mario_X]
    add ax, 12
    mov bx, [Mario_Y]
    add bx, dx
    call Test_Solid_At
    cmp al, 1
    je near Landed_On_Tile
    mov byte [Mario_On_Gnd], 0
    jmp Check_Map_Pickups
	; Snap Mario onto the top of solid ground, reset vertical speed, and clear stomp chain.
Landed_On_Tile:
    mov ax, [Mario_Y]
    add ax, dx
    and ax, 0FFF0h
    sub ax, dx
    mov [Mario_Y], ax
    mov byte [Mario_Y_Sub], 0
    mov word [Mario_Vy], 0
    mov byte [Mario_On_Gnd], 1
    mov byte [Stomp_Chain], 0
    jmp Check_Map_Pickups
Check_Head_Hit:
    mov ax, [Mario_X]
    add ax, 8
    mov bx, [Mario_Y]
    call Test_Solid_At
    cmp al, 1
    jne near Check_Map_Pickups
    mov ax, [Mario_Y]
    and ax, 0FFF0h
    add ax, TILE_SIZE
    mov [Mario_Y], ax
    mov word [Mario_Vy], 0
    mov ax, [Mario_X]
    add ax, 8
    mov bx, [Mario_Y]
    sub bx, 2
    call Hit_Block_At
	; Check for overlapping map coins or flagpole tiles at Mario's body points.
Check_Map_Pickups:
    mov ax, [Mario_X]
    add ax, 8
    mov bx, [Mario_Y]
    add bx, 8
    call Check_Single_Pickup
    cmp byte [Level_Won], 1
    je near Pickup_Done
    mov ax, [Mario_X]
    add ax, 13
    mov bx, [Mario_Y]
    add bx, 12
    call Check_Single_Pickup
Pickup_Done:
    ret
Check_Single_Pickup:
    call Get_Tile_Index
    cmp di, MAP_TILES
    jae near Single_Pick_Done
    mov al, [Map_Working + di]
    cmp al, 11
    jne near Check_Flag_Tile
    mov byte [Map_Working + di], 0
    call Add_Coin
    mov ax, 200
    call Spawn_Popup
    push 0
    push 200
    call Add_Score32
    jmp Single_Pick_Done
	; Handle flagpole contact and award points based on Mario's vertical height.
Check_Flag_Tile:
    cmp al, 12
    jne near Single_Pick_Done
    mov byte [Level_Won], 1
    mov ax, [Mario_Y]
    sar ax, 4
    cmp ax, 3
    jle near Flag_5000
    cmp ax, 4
    je near Flag_2000
    cmp ax, 5
    je near Flag_800
    cmp ax, 7
    jle near Flag_400
    mov ax, 100
    call Spawn_Popup
    push 0
    push 100
    call Add_Score32
    jmp Single_Pick_Done
	
	; Award points for touching the section of the flagpole.
	
Flag_5000:
    mov ax, 5000
    call Spawn_Popup
    push 0
    push 5000
    call Add_Score32
    jmp Single_Pick_Done
Flag_2000:
    mov ax, 2000
    call Spawn_Popup
    push 0
    push 2000
    call Add_Score32
    jmp Single_Pick_Done
Flag_800:
    mov ax, 800
    call Spawn_Popup
    push 0
    push 800
    call Add_Score32
    jmp Single_Pick_Done
Flag_400:
    mov ax, 400
    call Spawn_Popup
    push 0
    push 400
    call Add_Score32
Single_Pick_Done:
    ret
	; Convert world pixel coordinates (AX, BX) into a level map array index in DI.
Get_Tile_Index:
    cmp bx, 0
    jl near Bad_Tile_Idx
    cmp bx, LEVEL_H
    jge near Bad_Tile_Idx
    cmp ax, 0
    jl near Bad_Tile_Idx
    cmp ax, LEVEL_W
    jge near Bad_Tile_Idx
    push ax
    push bx
    shr bx, 4
    mov ax, bx
    mov bl, MAP_COLS
    mul bl
    mov di, ax
    pop bx
    pop ax
    push ax
    shr ax, 4
    add di, ax
    pop ax
    ret
Bad_Tile_Idx:
    mov di, MAP_TILES
    ret
	; Return AL = 1 if the tile at (AX, BX) is solid, or 0 otherwise.
Test_Solid_At:
    push di
    call Get_Tile_Index
    cmp di, MAP_TILES
    jae near Not_Solid
    mov al, [Map_Working + di]
    cmp al, 0
    je near Not_Solid
    cmp al, 11
    je near Not_Solid
    cmp al, 12
    je near Not_Solid
    mov al, 1
    pop di
    ret
Not_Solid:
    xor al, al
    pop di
    ret
	; Trigger brick breaking or question block rewards when hit from below.
Hit_Block_At:
    push di
    call Get_Tile_Index
    cmp di, MAP_TILES
    jae near Hit_Blk_Done
    mov al, [Map_Working + di]
    cmp al, 2
    jne near Check_Q_Coin
    cmp byte [Mario_Hp], 2
    jne near Hit_Blk_Done
    mov byte [Map_Working + di], 0
    mov ax, 50
    call Spawn_Popup
    push 0
    push 50
    call Add_Score32
    jmp Hit_Blk_Done
Check_Q_Coin:
    cmp al, 3
    jne near Check_Q_Mush
    mov byte [Map_Working + di], 5
    call Add_Coin
    mov ax, 200
    call Spawn_Popup
    push 0
    push 200
    call Add_Score32
    jmp Hit_Blk_Done
	; Spawn a mushroom power up above a mushroom question block.
Check_Q_Mush:
    cmp al, 4
    jne near Hit_Blk_Done
    mov byte [Map_Working + di], 5
    mov byte [Mush_Active], 1
    and ax, 0FFF0h
    mov [Mush_X], ax
    and bx, 0FFF0h
    sub bx, TILE_SIZE
    mov [Mush_Y], bx
    mov word [Mush_Vx], 1
    mov word [Mush_Vy], 0
Hit_Blk_Done:
    pop di
    ret
; Camera, Mushroon and Enemies 
; Advance the camera when Mario passes screen center without ever scrolling left.
Update_Camera:
    mov ax, [Mario_X]
    sub ax, 160
    cmp ax, [Camera_X]
    jle near Cam_Left_Wall
    cmp ax, MAX_CAM_X
    jle near Set_Cam_X
    mov ax, MAX_CAM_X
	; Set the new horizontal camera offset.
Set_Cam_X:
    mov [Camera_X], ax
Cam_Left_Wall:
    mov ax, [Camera_X]
    cmp [Mario_X], ax
    jge near Cam_Ok
    mov [Mario_X], ax
    mov word [Mario_Vx], 0
Cam_Ok:
    ret
	; Move the active power-up mushroom, reverse it at walls, and apply gravity.
Update_Mushroom:
    cmp byte [Mush_Active], 1
    jne near Mush_Done
    mov ax, [Mush_Vx]
    add [Mush_X], ax
    mov ax, [Mush_X]
    add ax, 8
    mov bx, [Mush_Y]
    add bx, 8
    call Test_Solid_At
    cmp al, 1
    jne near Mush_Fall
    neg word [Mush_Vx]
	; Apply downward gravity to the mushroom and snap it onto solid ground.
Mush_Fall:
    add word [Mush_Y], 2
    mov ax, [Mush_X]
    add ax, 8
    mov bx, [Mush_Y]
    add bx, TILE_SIZE
    call Test_Solid_At
    cmp al, 1
    jne near Mush_Check_Pit
    and word [Mush_Y], 0FFF0h
Mush_Check_Pit:
    cmp word [Mush_Y], LEVEL_H
    jl near Mush_Done
    mov byte [Mush_Active], 0
Mush_Done:
    ret
Update_Enemies:
    mov cx, MAX_ENEMIES
    mov si, Enemy_Table
	; Process movement and timers for each active enemy record.
En_Loop:
    cmp byte [si], 0
    je near Next_En
    mov ax, [si+2]
    mov bx, [Camera_X]
    add bx, 336
    cmp ax, bx
    jg near Next_En
    cmp byte [si+1], 0
    jne near En_Active
    mov byte [si+1], 1
	; Switch enemy state from dormant to active once near the visible screen.
En_Active:
    cmp byte [si], 1
    jne near En_Move
    cmp byte [si+1], 2
    jne near En_Move
    dec byte [si+7]
    jnz near Next_En
    mov byte [si], 0
    jmp Next_En
	; Update enemy horizontal movement or sliding shell velocity.
En_Move:
    cmp byte [si+1], 2
    je near En_Shell_Grace
    movsx ax, byte [si+6]
    cmp byte [si+1], 3
    jne near En_Apply_X
    imul ax, 3
En_Apply_X:
    add [si+2], ax
    mov ax, [si+2]
    cmp ax, 0
    jle near En_Turn_Right
    cmp ax, [Camera_X]
    jle near En_Turn_Right
    cmp ax, 944
    jge near En_Turn_Left
    jmp En_Wall_Chk
	; Reverse enemy direction to face right.
En_Turn_Right:
    mov byte [si+6], 1
    jmp En_Wall_Chk
	; Reverse enemy direction to face left.
En_Turn_Left:
    mov byte [si+6], -1
En_Wall_Chk:
    mov ax, [si+2]
    add ax, 8
    mov bx, [si+4]
    add bx, 8
    call Test_Solid_At
    cmp al, 1
    jne near En_Edge_Check
    neg byte [si+6]
    jmp En_Gravity
	; Check for platform edges ahead so Koopas turn around instead of falling.
En_Edge_Check:
    mov ax, [si+2]
    add ax, 2
    cmp byte [si+6], 1
    jne near En_Edge_Test
    add ax, 12
En_Edge_Test:
    mov bx, [si+4]
    add bx, 18
    call Test_Solid_At
    cmp al, 1
    je near En_Gravity
    neg byte [si+6]
	; Apply downward gravity and snap the enemy onto solid tiles.
En_Gravity:
    add word [si+4], 2
    mov ax, [si+2]
    add ax, 8
    mov bx, [si+4]
    add bx, TILE_SIZE
    call Test_Solid_At
    cmp al, 1
    jne near En_Pit_Chk
    and word [si+4], 0FFF0h
	; Remove the enemy record if it falls into a pit below the map.
En_Pit_Chk:
    cmp word [si+4], LEVEL_H
    jl near En_Shell_Grace
    mov byte [si], 0
    jmp Next_En
	; Decrement the kick grace timer so a kicked shell does not immediately hurt Mario.
En_Shell_Grace:
    cmp byte [si+7], 0
    je near Next_En
    dec byte [si+7]
	; Advance SI to the next 8 byte enemy record.
Next_En:
    add si, 8
    dec cx
    jnz near En_Loop
    ret
	; Check collisions between Mario and the mushroom power-up or active enemies.
Check_Entities:
    cmp byte [Mush_Active], 1
    jne near Check_En_Overlap
    mov ax, [Mario_X]
    sub ax, [Mush_X]
    cmp ax, -14
    jl near Check_En_Overlap
    cmp ax, 14
    jg near Check_En_Overlap
    mov ax, [Mario_Y]
    sub ax, [Mush_Y]
    cmp ax, -16
    jl near Check_En_Overlap
    cmp ax, TILE_SIZE
    jg near Check_En_Overlap
    mov byte [Mush_Active], 0
    mov ax, 1000
    call Spawn_Popup
    push 0
    push 1000
    call Add_Score32
    cmp byte [Mario_Hp], 1
    jne near Check_En_Overlap
    mov byte [Mario_Hp], 2
    sub word [Mario_Y], TILE_SIZE
Check_En_Overlap:
    mov cx, MAX_ENEMIES
    mov si, Enemy_Table
En_Col_Loop:
    cmp byte [si], 0
    je near Next_En_Col
    cmp byte [si], 1
    jne near En_Is_Koopa
    cmp byte [si+1], 2
    je near Next_En_Col
	; Handle Koopa Troopa and shell collision states.
En_Is_Koopa:
    mov ax, [Mario_X]
    sub ax, [si+2]
    cmp ax, -12
    jl near Next_En_Col
    cmp ax, 12
    jg near Next_En_Col
    mov bx, TILE_SIZE
    cmp byte [Mario_Hp], 2
    jne near En_Y_Test
    mov bx, 32
	; Compute vertical distance between Mario's feet and the enemy's top edge.
En_Y_Test:
    mov ax, [Mario_Y]
    add ax, bx
    sub ax, [si+4]
    cmp ax, 4
    jl near Next_En_Col
    cmp ax, TILE_SIZE
    jg near Next_En_Col
    cmp byte [si], 2
    jne near Test_Stomp
    cmp byte [si+1], 2
    jne near Test_Stomp
    mov byte [si+1], 3
    mov byte [si+7], 10
    mov byte [si+6], 1
    mov ax, [Mario_X]
    cmp ax, [si+2]
    jl near Kick_Right
    mov byte [si+6], -1
Kick_Right:
    mov ax, 400
    call Spawn_Popup
    push 0
    push 400
    call Add_Score32
    jmp Next_En_Col
	; Check if Mario is falling onto the enemy to perform a stomp bounce.
Test_Stomp:
    cmp word [Mario_Vy], 0
    jle near Hurt_Mario
    mov word [Mario_Vy], -768
    call Award_Stomp_Points
    cmp byte [si], 1
    jne near Stomp_Koopa
    mov byte [si+1], 2
    mov byte [si+7], 30
    jmp Next_En_Col
	; Turn a stomped Koopa Troopa into a stationary shell.
Stomp_Koopa:
    mov byte [si+1], 2
    mov byte [si+7], 10
    jmp Next_En_Col
	; Shrink Super Mario with invulnerability frames or kill Small Mario on side contact.
Hurt_Mario:
    cmp byte [si+7], 0
    jne near Next_En_Col
    cmp byte [Mario_Invuln], 0
    jne near Next_En_Col
    cmp byte [Mario_Hp], 2
    jne near Kill_Mario
    mov byte [Mario_Hp], 1
    add word [Mario_Y], TILE_SIZE
    mov byte [Mario_Invuln], 60
    jmp Next_En_Col
	; Trigger Mario's death sequence when hit at 1 HP.
Kill_Mario:
    mov byte [Death_Pit], 0
    call Trigger_Death
    ret
Next_En_Col:
    add si, 8
    dec cx
    jnz near En_Col_Loop
    ret
Award_Stomp_Points:
    xor bx, bx
    mov bl, [Stomp_Chain]
    cmp bl, 10
    jae near Stomp_1up
    shl bx, 1
    mov ax, [Stomp_Table + bx]
    call Spawn_Popup
    push 0
    push ax
    call Add_Score32
    inc byte [Stomp_Chain]
    ret
	; Grant an extra life when the consecutive stomp chain reaches 10 or more.
Stomp_1up:
    inc byte [Lives]
    ret
; Scene Rendering, Clouds Scenery, Hud and Font
Render_Scene:
    push COL_SKY
    call Clear_Buffer
    call Draw_Scenery
    call Draw_Map
    call Draw_Mushroom
    call Draw_Enemies
    call Draw_Mario
    call Draw_Popup
    call Draw_Hud
    ret
Draw_Scenery:
    mov ax, [Camera_X]
    shr ax, 1
    mov bx, 64
    sub bx, ax
    push bx
    push 30
    call Draw_Cloud
    mov ax, [Camera_X]
    shr ax, 1
    mov bx, 210
    sub bx, ax
    push bx
    push 44
    call Draw_Cloud
    mov ax, [Camera_X]
    shr ax, 1
    mov bx, 360
    sub bx, ax
    push bx
    push 28
    call Draw_Cloud
    mov ax, [Camera_X]
    shr ax, 1
    mov bx, 510
    sub bx, ax
    push bx
    push 40
    call Draw_Cloud
    mov bx, 912
    sub bx, [Camera_X]
    cmp bx, SCREEN_W
    jg near Scenery_Done
    cmp bx, -48
    jl near Scenery_Done
    push bx
    push 112
    push 36
    push 48
    push COL_RED
    call Fill_Rect
    mov ax, bx
    add ax, 12
    push ax
    push 136
    push 12
    push 24
    push COL_BLACK
    call Fill_Rect
Scenery_Done:
    ret
Draw_Cloud:
    push bp
    mov bp, sp
    mov ax, [bp+6]
    cmp ax, -48
    jl near Cloud_Done
    cmp ax, SCREEN_W
    jg near Cloud_Done
    push ax
    push word [bp+4]
    push 36
    push 10
    push COL_WHITE
    call Fill_Rect
    mov ax, [bp+6]
    add ax, 6
    mov bx, [bp+4]
    sub bx, 5
    push ax
    push bx
    push 24
    push 6
    push COL_WHITE
    call Fill_Rect
Cloud_Done:
    pop bp
    ret 4
Draw_Map:
    mov ax, [Camera_X]
    shr ax, 4
    mov [First_Col], ax
    mov word [Cur_Row], 1
Map_Row_Loop:
    mov word [Cur_Col], 0
Map_Col_Loop:
    mov ax, [First_Col]
    add ax, [Cur_Col]
    cmp ax, MAP_COLS
    jge near Next_Map_Row
    mov bx, [Cur_Row]
    imul bx, MAP_COLS
    add bx, ax
    mov al, [Map_Working + bx]
    cmp al, 0
    je near Next_Map_Col
    mov cx, [Cur_Col]
    shl cx, 4
    mov dx, [Camera_X]
    and dx, 15
    sub cx, dx
    mov dx, [Cur_Row]
    shl dx, 4
    push cx
    push dx
    push ax
    call Draw_Tile_Sprite
Next_Map_Col:
    inc word [Cur_Col]
    cmp word [Cur_Col], VIEW_COLS
    jl near Map_Col_Loop
Next_Map_Row:
    inc word [Cur_Row]
    cmp word [Cur_Row], MAP_ROWS
    jl near Map_Row_Loop
    ret
Draw_Tile_Sprite:
    push bp
    mov bp, sp
    mov al, [bp+4]
    cmp al, 1
    je near Tile_Is_Gnd
    cmp al, 2
    je near Tile_Is_Brick
    cmp al, 3
    je near Tile_Is_Q
    cmp al, 4
    je near Tile_Is_Q
    cmp al, 5
    je near Tile_Is_Empty
    cmp al, 6
    je near Tile_Is_PipeTop
    cmp al, 7
    je near Tile_Is_PipeTop
    cmp al, 10
    je near Tile_Is_Stair
    cmp al, 11
    je near Tile_Is_Coin
    cmp al, 12
    je near Tile_Is_Flag
    push word [bp+8]
    push word [bp+6]
    push TILE_SIZE
    push TILE_SIZE
    push COL_GREEN
    call Fill_Rect
    mov ax, [bp+8]
    add ax, 2
    push ax
    push word [bp+6]
    push 4
    push TILE_SIZE
    push COL_LGREEN
    call Fill_Rect
    pop bp
    ret 6
	; Draw the top lip and rim outline of a warp pipe.
Tile_Is_PipeTop:
    push word [bp+8]
    push word [bp+6]
    push TILE_SIZE
    push TILE_SIZE
    push COL_GREEN
    call Fill_Rect
    push word [bp+8]
    push word [bp+6]
    push TILE_SIZE
    push 4
    push COL_LGREEN
    call Fill_Rect
    mov ax, [bp+6]
    add ax, 4
    push word [bp+8]
    push ax
    push TILE_SIZE
    push 2
    push COL_BLACK
    call Fill_Rect
    pop bp
    ret 6
	; Draw a ground tile with brown dirt and a green grass top strip.
Tile_Is_Gnd:
    push word [bp+8]
    push word [bp+6]
    push TILE_SIZE
    push TILE_SIZE
    push COL_BROWN
    call Fill_Rect
    push word [bp+8]
    push word [bp+6]
    push TILE_SIZE
    push 3
    push COL_LGREEN
    call Fill_Rect
    pop bp
    ret 6
Tile_Is_Brick:
    push word [bp+8]
    push word [bp+6]
    push Spr_Brick_Unique
    push 0
    call Draw_Sprite
    pop bp
    ret 6
Tile_Is_Q:
    push word [bp+8]
    push word [bp+6]
    push Spr_QBlock_Unique
    push 0
    call Draw_Sprite
    pop bp
    ret 6
Tile_Is_Empty:
    push word [bp+8]
    push word [bp+6]
    push Spr_Empty_Unique
    push 0
    call Draw_Sprite
    pop bp
    ret 6
Tile_Is_Stair:
    push word [bp+8]
    push word [bp+6]
    push Spr_Stair_Unique
    push 0
    call Draw_Sprite
    pop bp
    ret 6
Tile_Is_Coin:
    push word [bp+8]
    push word [bp+6]
    push Spr_Coin_Unique
    push 0
    call Draw_Sprite
    pop bp
    ret 6
Tile_Is_Flag:
    mov ax, [bp+8]
    add ax, 6
    push ax
    push word [bp+6]
    push 4
    push TILE_SIZE
    push COL_WHITE
    call Fill_Rect
    cmp word [bp+6], 32
    jne near Flag_No_Banner
    mov ax, [bp+8]
    sub ax, 8
    push ax
    push 34
    push 14
    push 10
    push COL_LRED
    call Fill_Rect
Flag_No_Banner:
    pop bp
    ret 6
Draw_Mushroom:
    cmp byte [Mush_Active], 1
    jne near Draw_Mush_Done
    mov ax, [Mush_X]
    sub ax, [Camera_X]
    push ax
    push word [Mush_Y]
    push Spr_Mush_Unique
    push 0
    call Draw_Sprite
Draw_Mush_Done:
    ret
Draw_Enemies:
    mov cx, MAX_ENEMIES
    mov si, Enemy_Table
	; Loop through all eight enemy slots to render visible enemies.
Draw_En_Loop:
    cmp byte [si], 0
    je near Skip_Draw_En
    mov ax, [si+2]
    sub ax, [Camera_X]
    cmp ax, -16
    jl near Skip_Draw_En
    cmp ax, SCREEN_W
    jg near Skip_Draw_En
    mov bx, Spr_Goomba
    cmp byte [si], 2
    je near Draw_Check_Koopa
    cmp byte [si+1], 2
    jne near Do_Draw_En
    mov bx, Spr_Goomba_Flat
    jmp Do_Draw_En
Draw_Check_Koopa:
    mov bx, Spr_Koopa_Unique
    cmp byte [si+1], 2
    jb near Do_Draw_En
    mov bx, Spr_Shell_Unique
Do_Draw_En:
    push ax
    push word [si+4]
    push bx
    push 0
    call Draw_Sprite
Skip_Draw_En:
    add si, 8
    dec cx
    jnz near Draw_En_Loop
    ret
Draw_Mario:
    test byte [Mario_Invuln], 1
    jnz near Draw_Mario_Done
    mov ax, [Mario_X]
    sub ax, [Camera_X]
    xor dx, dx
    mov dl, [Mario_Facing]
    mov si, Spr_Mario_Small
    cmp byte [Mario_Hp], 2
    jne near Do_Draw_Mario
    or dl, 2
    mov si, Spr_Mario_Super
Do_Draw_Mario:
    push ax
    push word [Mario_Y]
    push si
    push dx
    call Draw_Sprite
Draw_Mario_Done:
    ret
	; Draw the top black HUD bar showing score, coins, world, timer, lives, and hearts.
Draw_Hud:
    push 0
    push 0
    push SCREEN_W
    push TILE_SIZE
    push COL_BLACK
    call Fill_Rect
    push 8
    push 1
    push COL_WHITE
    push Str_Hud_Score
    call Draw_String
    push 8
    push 8
    push COL_WHITE
    call Draw_Score6
    push 72
    push 1
    push COL_WHITE
    push Str_Hud_Coins
    call Draw_String
    push 72
    push 8
    push COL_YELLOW
    push 120
    call Draw_Char
    xor ax, ax
    mov al, [Coins]
    push 80
    push 8
    push COL_WHITE
    push ax
    push 2
    call Draw_Number
    push 128
    push 1
    push COL_WHITE
    push Str_Hud_World
    call Draw_String
    push 132
    push 8
    push COL_WHITE
    push Str_W11
    call Draw_String
    push 184
    push 1
    push COL_WHITE
    push Str_Hud_Time
    call Draw_String
    push 188
    push 8
    push COL_WHITE
    push word [Game_Time]
    push 3
    call Draw_Number
    push 232
    push 1
    push COL_WHITE
    push Str_Hud_Lives
    call Draw_String
    push 236
    push 8
    push COL_WHITE
    push 120
    call Draw_Char
    xor ax, ax
    mov al, [Lives]
    push 244
    push 8
    push COL_WHITE
    push ax
    push 1
    call Draw_Number
    push 272
    push 1
    push COL_WHITE
    push Str_Hud_Hp
    call Draw_String
    push 280
    push 8
    push COL_LRED
    push 3
    call Draw_Char
    mov ax, COL_DGRAY
    cmp byte [Mario_Hp], 2
    jne near Draw_H2
    mov ax, COL_LRED
Draw_H2:
    push 292
    push 8
    push ax
    push 3
    call Draw_Char
    ret
; Graphics and text
; Fill the entire 64,000-byte off-screen frame buffer with a solid color using REP STOSW.
Clear_Buffer:
    push bp
    mov bp, sp
    push ax
    push cx
    push di
    push es
    mov es, [Buffer_Seg]
    xor di, di
    mov ax, [bp+4]
    mov ah, al
    mov cx, SCREEN_WORDS
    rep stosw
    pop es
    pop di
    pop cx
    pop ax
    pop bp
    ret 2
	; Copy the completed off-screen frame buffer to VGA memory (0A000h) using REP MOVSW.
Flip_Buffer:
    push cx
    push si
    push di
    push ds
    push es
    mov ax, VGA_SEG
    mov es, ax
    mov ds, [cs:Buffer_Seg]
    xor si, si
    xor di, di
    mov cx, SCREEN_WORDS
    rep movsw
    pop es
    pop ds
    pop di
    pop si
    pop cx
    ret
	; Draw a clipped solid rectangle into the off-screen frame buffer.
Fill_Rect:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    mov es, [Buffer_Seg]
    mov dx, [bp+10]
    mov bx, [bp+6]
	; Loop vertically across each row of the rectangle.
Rect_Y_Loop:
    cmp dx, 0
    jl near Rect_Next_Y
    cmp dx, SCREEN_H
    jge near Rect_Done
    mov ax, dx
    mov di, ax
    shl di, 8
    shl ax, 6
    add di, ax
    add di, [bp+12]
    mov cx, [bp+8]
    mov ax, [bp+4]
	; Fill one horizontal scanline of pixels in the rectangle.
Rect_X_Loop:
    mov [es:di], al
    inc di
    loop Rect_X_Loop
Rect_Next_Y:
    inc dx
    dec bx
    jnz near Rect_Y_Loop
Rect_Done:
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 10
	; Draw a 16x16 or 16x32 transparent sprite with edge clipping and horizontal mirroring.
Draw_Sprite:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov es, [Buffer_Seg]
    mov si, [bp+6]
    mov dx, TILE_SIZE
    test word [bp+4], 2
    jz near Spr_Start
    mov dx, 32
Spr_Start:
    xor bx, bx
Spr_Row_Loop:
    mov ax, [bp+8]
    add ax, bx
    cmp ax, 0
    jl near Spr_Next_Row
    cmp ax, SCREEN_H
    jge near Spr_End
    mov di, ax
    shl di, 8
    shl ax, 6
    add di, ax
    xor cx, cx
Spr_Col_Loop:
    mov ax, [bp+10]
    add ax, cx
    cmp ax, 0
    jl near Spr_Next_Col
    cmp ax, SCREEN_W
    jge near Spr_Next_Col
    push bx
    mov bx, cx
    test word [bp+4], 1
    jz near Spr_No_Flip
    mov bx, 15
    sub bx, cx
Spr_No_Flip:
    mov al, [si + bx]
    pop bx
    cmp al, 0
    je near Spr_Next_Col
    push di
    add di, [bp+10]
    add di, cx
    mov [es:di], al
    pop di
Spr_Next_Col:
    inc cx
    cmp cx, TILE_SIZE
    jl near Spr_Col_Loop
Spr_Next_Row:
    add si, TILE_SIZE
    inc bx
    cmp bx, dx
    jl near Spr_Row_Loop
	; Restore registers and return from sprite drawing.
Spr_End:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 8
	; Convert the 32 bit score into six zero padded decimal digits and draw them.
Draw_Score6:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    mov ax, [Score_Lo]
    mov dx, [Score_Hi]
    mov bx, 10
    mov cx, 6
Sc_Div_Loop:
    push ax
    mov ax, dx
    xor dx, dx
    div bx
    mov si, ax
    pop ax
    div bx
    push dx
    mov dx, si
    loop Sc_Div_Loop
    mov cx, 6
    mov bx, [bp+8]
Sc_Prt_Loop:
    pop ax
    add al, 48
    push bx
    push word [bp+6]
    push word [bp+4]
    push ax
    call Draw_Char
    add bx, 8
    loop Sc_Prt_Loop
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 6
	; Convert a 16 bit integer into a fixed number of zero padded decimal digits.
Draw_Number:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    mov ax, [bp+6]
    mov cx, [bp+4]
    mov bx, 10
Num_Div_Loop:
    xor dx, dx
    div bx
    push dx
    loop Num_Div_Loop
    mov cx, [bp+4]
    mov bx, [bp+12]
	; Pop remainders in reverse order and draw each digit character.
Num_Prt_Loop:
    pop ax
    add al, 48
    push bx
    push word [bp+10]
    push word [bp+8]
    push ax
    call Draw_Char
    add bx, 8
    loop Num_Prt_Loop
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 10
	; Render an 8x8 ASCII character using the ROM BIOS font table at F000h:FA6Eh.
Draw_Char:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    mov es, [Buffer_Seg]
    mov ax, 0F000h
    mov ds, ax
    xor bx, bx
    mov bl, [bp+4]
    shl bx, 3
    mov si, 0FA6Eh
    add si, bx
    mov di, [bp+8]
    mov ax, di
    shl di, 8
    shl ax, 6
    add di, ax
    add di, [bp+10]
    mov dl, [bp+6]
    mov cx, 8
Ch_Row_Loop:
    lodsb
    push cx
    push di
    mov cx, 8
Ch_Col_Loop:
    shl al, 1
    jnc near Ch_Skip_Px
    mov [es:di], dl
Ch_Skip_Px:
    inc di
    loop Ch_Col_Loop
    pop di
    pop cx
    add di, SCREEN_W
    loop Ch_Row_Loop
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 8
	; Draw a null terminated ASCII string horizontally using Draw_Char.
Draw_String:
    push bp
    mov bp, sp
    push ax
    push bx
    push si
    mov bx, [bp+10]
    mov si, [bp+4]
	; Read the next character from the string until the null terminator is reached.
Str_Loop:
    lodsb
    or al, al
    jz near Str_Done
    xor ah, ah
    push bx
    push word [bp+8]
    push word [bp+6]
    push ax
    call Draw_Char
    add bx, 8
    jmp Str_Loop
	; Restore registers and return from string drawing.
Str_Done:
    pop si
    pop bx
    pop ax
    pop bp
    ret 8
; SPRITES
Spr_Mario_Small:
    db 0,0,0,0,0,4,4,4,4,4,0,0,0,0,0,0
    db 0,0,0,0,4,4,4,4,4,4,4,0,0,0,0,0
    db 0,0,0,0,6,14,14,14,14,14,0,0,0,0,0,0
    db 0,0,0,0,6,14,0,14,14,14,14,0,0,0,0,0
    db 0,0,0,0,6,14,14,14,14,14,14,0,0,0,0,0
    db 0,0,0,0,0,14,14,14,14,14,0,0,0,0,0,0
    db 0,0,0,0,4,4,1,4,4,1,4,4,0,0,0,0
    db 0,0,0,4,4,4,1,4,4,1,4,4,4,0,0,0
    db 0,0,4,4,4,4,1,1,1,1,4,4,4,4,0,0
    db 0,14,14,4,4,1,14,1,14,1,4,4,14,14,0,0
    db 0,14,14,4,4,1,1,1,1,1,4,4,14,14,0,0
    db 0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0
    db 0,0,0,0,1,1,1,0,0,1,1,1,0,0,0,0
    db 0,0,0,6,6,6,0,0,0,0,6,6,6,0,0,0
    db 0,0,6,6,6,6,0,0,0,0,6,6,6,6,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
; Super Mario 16x32 
Spr_Mario_Super:
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,4,4,4,4,4,4,0,0,0,0,0
    db 0,0,0,0,4,4,4,4,4,4,4,4,0,0,0,0
    db 0,0,0,4,4,4,4,4,4,4,4,4,4,0,0,0
    db 0,0,0,6,6,6,14,14,14,6,14,0,0,0,0,0
    db 0,0,6,14,6,14,14,14,14,6,14,14,0,0,0,0
    db 0,0,6,14,6,6,14,14,14,14,6,14,14,0,0,0
    db 0,0,6,6,14,14,14,14,6,6,6,6,0,0,0,0
    db 0,0,0,0,14,14,14,14,14,14,14,0,0,0,0,0
    db 0,0,0,4,4,1,4,4,4,1,4,4,0,0,0,0
    db 0,0,4,4,4,1,4,4,4,1,4,4,4,0,0,0
    db 0,4,4,4,4,1,1,1,1,1,4,4,4,4,0,0
    db 0,4,4,4,4,1,14,1,14,1,4,4,4,4,0,0
    db 14,14,4,4,1,1,1,1,1,1,1,4,4,14,14,0
    db 14,14,14,0,1,1,1,1,1,1,1,0,14,14,14,0
    db 14,14,0,0,1,1,1,1,1,1,1,0,0,14,14,0
    db 0,0,0,0,1,1,1,0,0,1,1,1,0,0,0,0
    db 0,0,0,0,1,1,1,0,0,1,1,1,0,0,0,0
    db 0,0,0,0,1,1,1,0,0,1,1,1,0,0,0,0
    db 0,0,0,0,1,1,1,0,0,1,1,1,0,0,0,0
    db 0,0,0,0,1,1,1,0,0,1,1,1,0,0,0,0
    db 0,0,0,0,1,1,1,0,0,1,1,1,0,0,0,0
    db 0,0,0,0,1,1,1,0,0,1,1,1,0,0,0,0
    db 0,0,0,0,1,1,1,0,0,1,1,1,0,0,0,0
    db 0,0,0,0,1,1,1,0,0,1,1,1,0,0,0,0
    db 0,0,0,6,6,6,6,0,0,6,6,6,6,0,0,0
    db 0,0,6,6,6,6,6,0,0,6,6,6,6,6,0,0
    db 0,6,6,6,6,6,6,0,0,6,6,6,6,6,6,0
    db 0,6,6,6,6,6,6,0,0,6,6,6,6,6,6,0
Spr_Brick_Unique:
    db 4,4,4,4,4,4,4,0,4,4,4,4,4,4,4,0
    db 4,12,12,12,12,12,4,0,4,12,12,12,12,12,4,0
    db 4,12,12,12,12,12,4,0,4,12,12,12,12,12,4,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 4,4,4,0,4,4,4,4,4,4,4,0,4,4,4,4
    db 12,12,4,0,4,12,12,12,12,12,4,0,4,12,12,12
    db 12,12,4,0,4,12,12,12,12,12,4,0,4,12,12,12
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 4,4,4,4,4,4,4,0,4,4,4,4,4,4,4,0
    db 4,12,12,12,12,12,4,0,4,12,12,12,12,12,4,0
    db 4,12,12,12,12,12,4,0,4,12,12,12,12,12,4,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 4,4,4,0,4,4,4,4,4,4,4,0,4,4,4,4
    db 12,12,4,0,4,12,12,12,12,12,4,0,4,12,12,12
    db 12,12,4,0,4,12,12,12,12,12,4,0,4,12,12,12
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
Spr_Empty_Unique:
    db 6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6
    db 6,0,8,8,8,8,8,8,8,8,8,8,8,8,0,6
    db 6,8,6,6,6,6,6,6,6,6,6,6,6,6,8,6
    db 6,8,6,6,6,6,6,6,6,6,6,6,6,6,8,6
    db 6,8,6,6,6,6,6,6,6,6,6,6,6,6,8,6
    db 6,8,6,6,6,6,6,6,6,6,6,6,6,6,8,6
    db 6,8,6,6,6,6,6,6,6,6,6,6,6,6,8,6
    db 6,8,6,6,6,6,6,6,6,6,6,6,6,6,8,6
    db 6,8,6,6,6,6,6,6,6,6,6,6,6,6,8,6
    db 6,8,6,6,6,6,6,6,6,6,6,6,6,6,8,6
    db 6,8,6,6,6,6,6,6,6,6,6,6,6,6,8,6
    db 6,8,6,6,6,6,6,6,6,6,6,6,6,6,8,6
    db 6,8,6,6,6,6,6,6,6,6,6,6,6,6,8,6
    db 6,8,6,6,6,6,6,6,6,6,6,6,6,6,8,6
    db 6,0,8,8,8,8,8,8,8,8,8,8,8,8,0,6
    db 6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6
Spr_Stair_Unique:
    db 15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,6
    db 15,42,42,42,42,42,42,42,42,42,42,42,42,42,6,6
    db 15,42,42,42,42,42,42,42,42,42,42,42,42,6,6,6
    db 15,42,42,42,42,42,42,42,42,42,42,42,42,6,6,6
    db 15,42,42,42,42,42,42,42,42,42,42,42,42,6,6,6
    db 15,42,42,42,42,42,42,42,42,42,42,42,42,6,6,6
    db 15,42,42,42,42,42,42,42,42,42,42,42,42,6,6,6
    db 15,42,42,42,42,42,42,42,42,42,42,42,42,6,6,6
    db 15,42,42,42,42,42,42,42,42,42,42,42,42,6,6,6
    db 15,42,42,42,42,42,42,42,42,42,42,42,42,6,6,6
    db 15,42,42,42,42,42,42,42,42,42,42,42,42,6,6,6
    db 15,42,42,42,42,42,42,42,42,42,42,42,42,6,6,6
    db 15,42,42,42,42,42,42,42,42,42,42,42,42,6,6,6
    db 15,42,6,6,6,6,6,6,6,6,6,6,6,6,6,6
    db 15,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6
    db 6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6
Spr_Goomba:
    db 0,0,0,0,0,0,6,6,6,6,0,0,0,0,0,0
    db 0,0,0,0,0,6,6,6,6,6,6,0,0,0,0,0
    db 0,0,0,0,6,6,6,6,6,6,6,6,0,0,0,0
    db 0,0,0,6,6,15,15,6,6,15,15,6,6,0,0,0
    db 0,0,6,6,6,15,0,6,6,0,15,6,6,6,0,0
    db 0,6,6,6,6,15,15,6,6,15,15,6,6,6,6,0
    db 0,6,6,6,6,6,6,6,6,6,6,6,6,6,6,0
    db 6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6
    db 6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6
    db 0,6,6,6,6,6,6,6,6,6,6,6,6,6,6,0
    db 0,0,0,0,0,14,14,14,14,14,14,0,0,0,0,0
    db 0,0,0,0,0,14,14,14,14,14,14,0,0,0,0,0
    db 0,0,0,15,15,15,0,0,0,0,15,15,15,0,0,0
    db 0,0,15,15,15,15,0,0,0,0,15,15,15,15,0,0
    db 0,0,15,15,15,15,0,0,0,0,15,15,15,15,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
Spr_Goomba_Flat:
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,6,6,6,6,6,6,6,6,6,6,6,6,0,0
    db 6,6,6,6,15,15,6,6,15,15,6,6,6,6,6,6
    db 6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6
    db 0,0,0,14,14,14,14,14,14,14,14,0,0,0,0,0
    db 0,0,15,15,15,0,0,0,0,0,15,15,15,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
Spr_Koopa_Unique:
    db 0,0,0,0,0,0,10,10,10,10,0,0,0,0,0,0
    db 0,0,0,0,0,10,15,10,15,10,10,0,0,0,0,0
    db 0,0,0,0,0,10,10,10,10,10,0,0,0,0,0,0
    db 0,0,0,0,0,0,14,14,14,0,0,0,0,0,0,0
    db 0,0,0,0,2,2,2,2,2,2,2,2,0,0,0,0
    db 0,0,0,2,2,10,2,2,2,10,2,2,2,0,0,0
    db 0,0,2,2,10,10,2,2,2,10,10,2,2,2,0,0
    db 0,0,2,2,2,2,2,2,2,2,2,2,2,2,0,0
    db 0,0,2,2,2,2,2,2,2,2,2,2,2,2,0,0
    db 0,0,15,15,15,15,15,15,15,15,15,15,15,15,0,0
    db 0,0,0,15,15,15,15,15,15,15,15,15,15,0,0,0
    db 0,0,0,0,14,14,0,0,0,0,14,14,0,0,0,0
    db 0,0,0,14,14,14,0,0,0,0,14,14,14,0,0,0
    db 0,0,14,14,14,14,0,0,0,0,14,14,14,14,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
Spr_Shell_Unique:
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,2,2,2,2,2,2,2,2,0,0,0,0
    db 0,0,2,2,2,10,10,2,2,10,10,2,2,2,0,0
    db 0,2,2,10,10,2,2,10,10,2,2,10,10,2,2,0
    db 0,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0
    db 2,2,10,10,2,2,10,10,10,10,2,2,10,10,2,2
    db 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2
    db 15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15
    db 0,15,15,15,15,15,15,15,15,15,15,15,15,15,15,0
    db 0,0,15,15,15,15,15,15,15,15,15,15,15,15,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
Spr_QBlock_Unique:
    db 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    db 14,6,6,6,6,6,6,6,6,6,6,6,6,6,6,14
    db 14,6,14,14,14,14,14,14,14,14,14,14,14,14,6,14
    db 14,6,14,14,14,6,6,6,6,6,14,14,14,14,6,14
    db 14,6,14,14,6,6,14,14,14,6,6,14,14,14,6,14
    db 14,6,14,14,6,6,14,14,14,6,6,14,14,14,6,14
    db 14,6,14,14,14,14,14,14,6,6,14,14,14,14,6,14
    db 14,6,14,14,14,14,14,6,6,14,14,14,14,14,6,14
    db 14,6,14,14,14,14,14,6,6,14,14,14,14,14,6,14
    db 14,6,14,14,14,14,14,14,14,14,14,14,14,14,6,14
    db 14,6,14,14,14,14,14,6,6,14,14,14,14,14,6,14
    db 14,6,14,14,14,14,14,6,6,14,14,14,14,14,6,14
    db 14,6,14,14,14,14,14,14,14,14,14,14,14,14,6,14
    db 14,6,14,14,14,14,14,14,14,14,14,14,14,14,6,14
    db 14,6,6,6,6,6,6,6,6,6,6,6,6,6,6,14
    db 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
Spr_Coin_Unique:
    db 0,0,0,0,0,0,14,14,14,14,0,0,0,0,0,0
    db 0,0,0,0,0,14,14,15,15,14,14,0,0,0,0,0
    db 0,0,0,0,14,14,15,14,14,15,14,14,0,0,0,0
    db 0,0,0,0,14,14,15,14,14,15,14,14,0,0,0,0
    db 0,0,0,0,14,14,15,14,14,15,14,14,0,0,0,0
    db 0,0,0,0,14,14,15,14,14,15,14,14,0,0,0,0
    db 0,0,0,0,14,14,15,14,14,15,14,14,0,0,0,0
    db 0,0,0,0,14,14,15,14,14,15,14,14,0,0,0,0
    db 0,0,0,0,14,14,15,14,14,15,14,14,0,0,0,0
    db 0,0,0,0,14,14,15,14,14,15,14,14,0,0,0,0
    db 0,0,0,0,14,14,15,14,14,15,14,14,0,0,0,0
    db 0,0,0,0,14,14,15,14,14,15,14,14,0,0,0,0
    db 0,0,0,0,0,14,14,15,15,14,14,0,0,0,0,0
    db 0,0,0,0,0,0,14,14,14,14,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
Spr_Mush_Unique:
    db 0,0,0,0,0,4,4,4,4,4,4,0,0,0,0,0
    db 0,0,0,4,4,4,15,15,4,4,4,4,4,0,0,0
    db 0,0,4,4,4,15,15,15,15,4,4,4,4,4,0,0
    db 0,4,4,4,4,15,15,15,15,4,4,15,15,4,4,0
    db 0,4,15,15,4,4,15,15,4,4,15,15,15,15,4,0
    db 4,15,15,15,15,4,4,4,4,4,15,15,15,15,4,4
    db 4,15,15,15,15,4,4,4,4,4,4,15,15,4,4,4
    db 4,4,15,15,4,4,4,4,4,4,4,4,4,4,4,4
    db 0,4,4,4,4,4,4,4,4,4,4,4,4,4,4,0
    db 0,0,0,14,14,14,14,14,14,14,14,14,14,0,0,0
    db 0,0,0,14,14,0,14,14,14,0,14,14,14,0,0,0
    db 0,0,0,14,14,0,14,14,14,0,14,14,14,0,0,0
    db 0,0,0,14,14,14,14,14,14,14,14,14,14,0,0,0
    db 0,0,0,0,14,14,14,14,14,14,14,14,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
; Variables (Hero, Enemies, Score, Clock, Keys)


; Hero Variables (mario & mushroom power up) 
Mario_X         dw 0
Mario_X_Sub     db 0
Mario_Y         dw 0
Mario_Y_Sub     db 0
Mario_Vx        dw 0
Mario_Vy        dw 0
Mario_On_Gnd    db 0
Mario_Facing    db 0
Mario_Hp        db 1
Mario_Invuln    db 0
Stomp_Chain     db 0
Death_Pit       db 0

Mush_Active     db 0
Mush_X          dw 0
Mush_Y          dw 0
Mush_Vx         dw 0
Mush_Vy         dw 0

;Enemy Variables 
Enemy_Init:
    db 1, 0
    dw 176, 144
    db -1, 0
    db 1, 0
    dw 256, 144
    db -1, 0
    db 2, 0
    dw 416, 144
    db -1, 0
    db 1, 0
    dw 512, 144
    db -1, 0
    db 1, 0
    dw 560, 144
    db -1, 0
    db 2, 0
    dw 688, 144
    db -1, 0
    db 1, 0
    dw 736, 144
    db -1, 0
    db 1, 0
    dw 784, 144
    db -1, 0
Enemy_Table:
    times 64 db 0

;Score, Camera & Hud Variables 
Camera_X        dw 0
Score_Lo        dw 0
Score_Hi        dw 0
Coins           db 0
Lives           db START_LIVES
Time_Bonus      dw 0

Popup_Timer     db 0
Popup_X         dw 0
Popup_Y         dw 0
Popup_Val       dw 0

First_Col       dw 0
Cur_Row         dw 0
Cur_Col         dw 0

Stomp_Table     dw 100, 200, 400, 500, 800, 1000, 2000, 4000, 5000, 8000
Str_Title1      db "SUPER MARIO", 0
Str_Title2      db "ENGINE", 0
Str_Start       db "START GAME", 0
Str_Exit        db "EXIT", 0
Str_Credits     db "Uswa, Maheen, Aania", 0
Str_Paused      db "PAUSED", 0
Str_Resume      db "Press P to resume", 0
Str_World       db "WORLD 1-1", 0
Str_Lifelost    db "LIVES LEFT", 0
Str_Complete    db "LEVEL COMPLETE!", 0
Str_Lbl_Score   db "SCORE", 0
Str_Lbl_Coins   db "COINS", 0
Str_Lbl_Bonus   db "TIME BONUS", 0
Str_Gameover    db "GAME OVER", 0
Str_Final_Sc    db "FINAL SCORE:", 0
Str_Enter_Cont  db "Press ENTER to continue", 0
Str_Hud_Score   db "SCORE", 0
Str_Hud_Coins   db "COINS", 0
Str_Hud_World   db "WORLD", 0
Str_W11         db "1-1", 0
Str_Hud_Time    db "TIME", 0
Str_Hud_Lives   db "LIVES", 0
Str_Hud_Hp      db "HEALTH", 0

;Clock, system and Game State Variables
Buffer_Seg      dw 0
Old_Int09_Off   dw 0
Old_Int09_Seg   dw 0
Old_Int08_Off   dw 0
Old_Int08_Seg   dw 0

Tick_Flag       db 0
Pit_Div         db 0
Sec_Ticks       db 0
Game_Time       dw START_TIME
Game_State      db ST_TITLE
Menu_Choice     db 0
Seq_Timer       db 0
Level_Won       db 0

;Keyboard Varaible 
Key_Table       times 128 db 0

; 60x12 LEVEL MAP
Map_Original:
    ; Row 0 : HUD
    times 60 db 0
    ; Row 1  : Sky
    times 60 db 0
    ; Row 2  : Flagpole top at col 56
    times 56 db 0
    db 12, 0, 0, 0
    ; Row 3  : Flagpole at col 56
    times 56 db 0
    db 12, 0, 0, 0
    ; Row 4  : Coins over Pit 1 (cols 21..23) and Pit 2 (cols 38..40), Flag at 56
    times 21 db 0
    db 11, 11, 11
    times 14 db 0
    db 11, 11, 11
    times 15 db 0
    db 12, 0, 0, 0
    ; Row 5  : Coins at cols 21..23, Flag at 56
    times 21 db 0
    db 11, 11, 11
    times 32 db 0
    db 12, 0, 0, 0
    ; Row 6  : Reachable ?/Brick/Solid row (cols 7..16), Stair top (col 53), Flag at 56
    times 7 db 0
    db 4, 0, 0, 2, 3, 2, 4, 2, 5, 3
    times 36 db 0
    db 10, 0, 0, 12, 0, 0, 0
    ; Row 7  : 3-high Pipe top at cols 28..29, Stairs (52..53), Flag at 56
    times 28 db 0
    db 6, 7
    times 22 db 0
    db 10, 10, 0, 0, 12, 0, 0, 0
    ; Row 8  : 2-high Pipe top (18..19), 3-high Pipe body (28..29), Stairs (51..53), Flag at 56
    times 18 db 0
    db 6, 7
    times 8 db 0
    db 8, 9
    times 21 db 0
    db 10, 10, 10, 0, 0, 12, 0, 0, 0
    ; Row 9  : Pipe 1 (18..19), Block after Pit 1 (24), Pipe 2 (28..29), Block after Pit 2 (41), Stairs (50..53), Flag base (56)
    times 18 db 0
    db 8, 9
    times 4 db 0
    db 5
    times 3 db 0
    db 8, 9
    times 11 db 0
    db 5
    times 8 db 0
    db 10, 10, 10, 10, 0, 0, 10, 0, 0, 0
    ; Row 10  : Ground with Pit 1 (21..23) and Pit 2 (38..40)
    times 21 db 1
    times 3 db 0
    times 14 db 1
    times 3 db 0
    times 19 db 1
    ; Row 11  : Ground bottom
    times 21 db 1
    times 3 db 0
    times 14 db 1
    times 3 db 0
    times 19 db 1
Map_Working:
    times 720 db 0