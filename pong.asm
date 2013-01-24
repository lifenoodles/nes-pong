;Completely 100% original NES game
;Not infringing on anything already existing
; - Donagh Hatton 04/02/2012

  .inesprg 1   ; 1x 16KB PRG code
  .ineschr 1   ; 1x  8KB CHR data
  .inesmap 0   ; mapper 0 = NROM, no bank swapping
  .inesmir 1   ; background mirroring
  
;;;;;;;;;;;;;;;

  .rsset $0000
  
controller1	.rs 1
controller2	.rs 1
score1		.rs 1
score2		.rs 1
paddle1 	.rs 1
paddle2		.rs 1
ballDirX	.rs 1
ballDirY	.rs 1
ballXspeed	.rs 1
ballYspeed	.rs 1
ballSpeed	.rs 1
gameState	.rs 1
numBounces	.rs 1
ballState	.rs 1 ;0 = moving, 1/2 = waiting for player
random		.rs 1
resetFlag	.rs 1
canCollide	.rs 1
numPlayers	.rs 1
aiWaitFrame	.rs 1
menuWait	.rs 1
  
WALL_LEFT	= $08
WALL_RIGHT	= $F8 ;see if this works out
WALL_TOP	= $17
WALL_BOTTOM	= $D8
BALL_X		= $0203
BALL_Y		= $0200
PADDLE1_X	= $08
PADDLE2_X	= $F0
PADDLE_HEIGHT	= $20
BALL_DIST	= $08
WINNING_SCORE	= $0A
  
  .bank 0
  .org $C000 
  
RESET:
  SEI          ; disable IRQs
  CLD          ; disable decimal mode
  LDX #$0F
  STX $4015    ; enable all channels
  LDX #$FF
  TXS          ; Set up stack
  INX          ; now X = 0
  ;STX $4010    ; disable DMC IRQs
  LDA #%0001000
  STA $2000
  
  JSR vblankwait
  
clrmem:
  LDA #$00
  STA $0000, x
  STA $0100, x
  STA $0300, x
  STA $0400, x
  STA $0500, x
  STA $0600, x
  STA $0700, x
  LDA #$FE
  STA $0200, x    ;move all sprites off screen
  INX
  BNE clrmem
  
  JSR vblankwait
  
  LoadSprites:
  LDX #$00
LoadSpritesLoop:
  LDA sprites, X
  STA $0200, X
  INX
  CPX #$24
  BNE LoadSpritesLoop
  
LoadPalettes:
  LDA $2002    ; read PPU status to reset the high/low latch
  LDA #$3F
  STA $2006    ; write the high byte of $3F00 address
  LDA #$00
  STA $2006    ; write the low byte of $3F00 address
  LDX #$00
LoadPalettesLoop:
  LDA palette, X        ;load palette byte
  STA $2007             ;write to PPU
  INX                   ;set index to next byte
  CPX #$20            
  BNE LoadPalettesLoop  ;if x = $20, 32 bytes copied, all done
  
  LDA #$00 ;start game at main menu, at player1
  STA gameState
  STA numPlayers
  STA menuWait
 
  JSR LoadStateMainMenu

Forever: ;cycle through numbers so we can use one as a "random" byte
  INC random
  JMP Forever     ;infinite loop except when NMI
  
NMI:
  LDA #$00   ; DMA all the sprite data in from 0200
  STA $2003  ; set the low byte (00) of the RAM address
  LDA #$02
  STA $4014  ; start DMA
  
  LDA gameState
  CMP #$01
  BNE NotGameState1
  JSR ReadController
  JSR HandleInput
  JSR PaddleCollisionDetection
  JSR SetPaddlePositions
  JSR MoveBall
  JSR BallCollisionDetection
  JMP MainLoopDone
NotGameState1: 
  CMP #$00
  BNE NotGameState0
  JSR ReadController
  JSR HandleInputMenu
  JMP MainLoopDone
NotGameState0:
  JSR ReadController
  JSR HandleInputEnd
MainLoopDone:
  RTI

MoveBall:
  ;check ball state
  LDA ballState
  BEQ MoveBallInX ;if zero
  ;else adjust ball based on paddle 1/2
  SEC
  SBC #$01
  BNE MoveBallWithPaddle2
  ;else move ball with paddle1
  LDA #PADDLE1_X
  CLC 
  ADC #BALL_DIST
  STA BALL_X
  LDA paddle1
  CLC 
  ADC #$0C
  STA BALL_Y
  JMP MoveBallFinished
MoveBallWithPaddle2:
  LDA #PADDLE2_X
  SEC 
  SBC #BALL_DIST
  ;SEC
  ;SBC #$08
  STA BALL_X
  LDA paddle2
  CLC 
  ADC #$0C
  STA BALL_Y
  JMP MoveBallFinished
MoveBallInX:
  LDA ballDirX
  BEQ MoveBallRight
  ;else move left
  LDA BALL_X
  SEC
  SBC ballXspeed
  STA BALL_X
  JMP MoveBallInY
MoveBallRight:
  LDA BALL_X
  CLC
  ADC ballXspeed
  STA BALL_X
MoveBallInY:
  LDA ballDirY
  BEQ MoveBallDown
  LDA BALL_Y
  SEC
  SBC ballYspeed
  STA BALL_Y
  JMP MoveBallFinished
MoveBallDown:
  LDA BALL_Y
  CLC
  ADC ballYspeed
  STA BALL_Y
MoveBallFinished:  
  RTS

;(SUB)  
BallCollisionDetection:
  ;check for top wall collision
  LDA BALL_Y
  CMP #WALL_TOP
  BCS BallNotTooHigh
  JSR PlayBeep1
  LDA #WALL_TOP
  STA BALL_Y
  LDA ballDirY
  EOR #$01
  STA ballDirY
BallNotTooHigh:
  ;check for bottom wall collision
  LDA BALL_Y
  CLC
  ADC #$08
  CMP #WALL_BOTTOM
  BCC BallNotTooLow
  JSR PlayBeep1
  LDA #WALL_BOTTOM
  SEC
  SBC #$08
  STA BALL_Y
  LDA ballDirY
  EOR #$01
  STA ballDirY
BallNotTooLow:
  ;check for left wall collision
  LDA BALL_X
  CLC
  ADC #$08
  CMP #WALL_LEFT
  BCS BallNotTooLeft
  JSR GoalScore
  JSR PlayBeep2
  RTS
BallNotTooLeft:
  ;check for right wall collision
  LDA BALL_X
  CMP #WALL_RIGHT
  BCC BallNotTooRight
  JSR GoalScore
  JSR PlayBeep2
  RTS
BallNotTooRight:
  ;check that ball can collide with left paddle
  LDA canCollide
  BEQ CheckLeftPaddle
  SEC
  SBC #$01
  BEQ DontJump1
  JMP CheckRightPaddle
DontJump1:
  ;check for left paddle collision
CheckLeftPaddle:
  LDA #PADDLE1_X
  CLC
  ADC #$08
  CMP BALL_X
  BCS DontJump2
  JMP CheckRightPaddle
DontJump2:
  LDA BALL_Y
  CLC
  ADC #$08
  CMP paddle1
  BCS DontJump3
  JMP CheckRightPaddle
DontJump3:
  LDA paddle1
  CLC
  ADC #PADDLE_HEIGHT
  CMP BALL_Y
  BCS DontJump4
  JMP CheckRightPaddle
DontJump4:  
  ;ball has hit left paddle, sort it out
  ;reverse x direction, always do this
  JSR PlayBeep3
  INC numBounces
  LDA ballDirX
  EOR #$01
  STA ballDirX
  ;set left paddle immune to collision
  LDA #$02
  STA canCollide  
  ;check if ball has hit top section
  LDA paddle1
  CLC 
  ADC #$0C
  CMP BALL_Y
  BCC BallNotHitTopSectionOfLeft
  ;ball has hit top section, check if hit very top
  ;get y and x intersection, compare them
  LDA BALL_Y
  CLC
  ADC #$08
  SEC
  SBC paddle1
  STA $FF
  LDA #PADDLE1_X
  CLC
  ADC #$08
  SEC
  SBC BALL_X
  CMP $FF
  BCC BallNotHitTopOfLeft
  ;ball has hit very top of left
  LDA #$01
  STA ballDirY
  LDA ballSpeed
  CLC
  ADC ballSpeed
  STA ballYspeed
  JMP BallCollisionDone
BallNotHitTopOfLeft:
  LDA #$01
  STA ballDirY
  LDA ballSpeed
  STA ballYspeed
  JMP BallCollisionDone
BallNotHitTopSectionOfLeft:
  LDA paddle1
  CLC 
  ADC #PADDLE_HEIGHT
  SEC
  SBC #$18
  CMP BALL_Y
  BCS BallNotHitBottomSectionOfLeft
  ;ball hit bottom section of left
  LDA paddle1
  CLC
  ADC #PADDLE_HEIGHT
  SEC
  SBC BALL_Y
  STA $FF
  LDA #PADDLE1_X
  CLC
  ADC #$08
  SEC
  SBC BALL_X
  CMP $FF
  BCC BallNotHitBottomOfLeft
  ;ball has hit very bottom of left
  LDA #$00
  STA ballDirY
  LDA ballSpeed
  CLC
  ADC ballSpeed
  STA ballYspeed
  JMP BallCollisionDone
BallNotHitBottomOfLeft:
  LDA #$00
  STA ballDirY
  LDA ballSpeed
  STA ballYspeed
  JMP BallCollisionDone
BallNotHitBottomSectionOfLeft:
  ;ball has hit center
  LDA #$00
  STA ballYspeed
  JMP BallCollisionDone

CheckRightPaddle:
  ;check if right paddle can be collided with
  LDA canCollide
  SEC
  SBC #$02
  BEQ DontJump5
  JMP BallCollisionDone
DontJump5:
  ;check for right paddle collision
  LDA #PADDLE2_X
  SEC
  SBC #$08
  CMP BALL_X
  BCC DontJump6
  JMP BallNotHitRightPaddle
DontJump6:
  LDA BALL_Y
  CLC
  ADC #$08
  CMP paddle2
  BCS DontJump7
  JMP BallNotHitRightPaddle
DontJump7:
  LDA paddle2
  CLC
  ADC #PADDLE_HEIGHT
  CMP BALL_Y
  BCS DontJump8
  JMP BallNotHitRightPaddle
DontJump8:
  ;ball has hit right paddle, sort it out
  ;reverse x direction, always do this
  JSR PlayBeep3
  INC numBounces
  LDA ballDirX
  EOR #$01
  STA ballDirX
  ;set right paddle immune to collision
  LDA #$01
  STA canCollide  
  ;check if ball has hit top section
  LDA paddle2
  CLC 
  ADC #$0C
  CMP BALL_Y
  BCC BallNotHitTopSectionOfRight
  ;ball has hit top section, check if hit very top
  ;get y and x intersection, compare them
  LDA BALL_Y
  CLC
  ADC #$08
  SEC
  SBC paddle2
  STA $FF
  LDA BALL_X
  CLC
  ADC #$08
  SBC #PADDLE2_X
  CMP $FF
  BCC BallNotHitTopOfRight
  ;ball has hit very top of right
  LDA #$01
  STA ballDirY
  LDA ballSpeed
  CLC
  ADC ballSpeed
  STA ballYspeed
  JMP BallCollisionDone
BallNotHitTopOfRight:
  LDA #$01
  STA ballDirY
  LDA ballSpeed
  STA ballYspeed
  JMP BallCollisionDone
BallNotHitTopSectionOfRight:
  LDA paddle2
  CLC 
  ADC #PADDLE_HEIGHT
  SEC
  SBC #$18
  CMP BALL_Y
  BCS BallNotHitBottomSectionOfRight
    ;ball hit bottom section of left
  LDA paddle2
  CLC
  ADC #PADDLE_HEIGHT
  SEC
  SBC BALL_Y
  STA $FF
  LDA BALL_X
  CLC
  ADC #$08
  SEC
  SBC #PADDLE2_X
  CMP $FF
  BCC BallNotHitBottomOfRight
  ;ball has hit very bottom of right
  LDA #$00
  STA ballDirY
  LDA ballSpeed
  CLC
  ADC ballSpeed
  STA ballYspeed
  JMP BallCollisionDone
BallNotHitBottomOfRight:
  LDA #$00
  STA ballDirY
  LDA ballSpeed
  STA ballYspeed
  JMP BallCollisionDone
BallNotHitBottomSectionOfRight:
  ;ball has hit center
  LDA #$00
  STA ballYspeed
  JMP BallCollisionDone
BallNotHitRightPaddle:
BallCollisionDone:
  LDA numBounces
  CMP #$04
  BNE NotSpeed2
  LDA #$02
  STA ballSpeed
  STA ballXspeed
NotSpeed2:
  CMP #$0A
  BNE NotSpeed3
  LDA #$03
  STA ballSpeed
  STA ballXspeed
NotSpeed3:
  RTS
  
;(SUB)
ReadController:
  LDA #$01 ;latch controllers so we can read from them
  STA $FF ;store $01 in 00FF so we can AND with it
  STA $4016
  LDA #$00
  STA $4016  
  ;start reading bytes from controllers
  ;we only care about the last bit in each case
  LDA $4016 ;p1 - A
  AND $FF
  ASL A
  STA controller1
  LDX #$00
ReadController1Loop:  
  LDA $4016 ;p1 - B, Sel, Sta, U, D, L
  AND $FF
  ORA controller1
  ASL A
  STA controller1
  INX
  CPX #$06
  BNE ReadController1Loop
  LDA $4016 ;p1 - R
  AND $FF
  ORA controller1
  STA controller1
  
  ;read second controller
  LDA $4017 ;p2 - A
  AND $FF
  ASL A
  STA controller2
  LDX #$00
ReadController2Loop: 
  LDA $4017 ;p2 - B, Sel, Sta, U, D, L
  AND $FF
  ORA controller2
  ASL A
  STA controller2
  INX
  CPX #$06
  BNE ReadController2Loop
  
  LDA $4017 ;p2 - Right
  AND $FF
  ORA controller2
  STA controller2
  
  RTS

;(SUB)  
HandleInput:
  ; bits in controller are a,b,sel,sta,u,d,l,r
  LDA controller1
  AND #%00001000 ; check if up pressed
  BEQ P1CheckDownPressed
  LDA paddle1
  SEC
  SBC #$02
  STA paddle1
P1CheckDownPressed:  
  LDA controller1
  AND #%00000100 ; check if down pressed
  BEQ P1CheckAPressed
  LDA paddle1
  CLC
  ADC #$02
  STA paddle1
P1CheckAPressed:  
  LDA controller1
  AND #%10000000 ; check if down pressed
  BEQ Control1CheckDone
  ;check if we have the ball
  LDA ballState
  SEC
  SBC #$01
  BNE Control1CheckDone
  ;if we do, set it in motion
  LDA #$00
  STA ballState
  STA ballDirX
  LDA #$01
  STA ballXspeed
  LDA random
  AND #%00000001
  STA ballDirY
  ;make paddle1 immune to collision
  LDA #$02
  STA canCollide
Control1CheckDone:  
  LDA numPlayers
  BNE Player2CheckControls
  JSR ControlAI
  JMP Control2CheckDone
Player2CheckControls:
  LDA controller2
  AND #%00001000 ; check if up pressed
  BEQ P2CheckDownPressed
  LDA paddle2
  SEC
  SBC #$02
  STA paddle2
P2CheckDownPressed:  
  LDA controller2
  AND #%00000100 ; check if down pressed
  BEQ P2CheckAPressed
  LDA paddle2
  CLC
  ADC #$02
  STA paddle2
P2CheckAPressed:  
  LDA controller2
  AND #%10000000 ; check if down pressed
  BEQ Control2CheckDone
  ;check if we have the ball
  LDA ballState
  SEC
  SBC #$02
  BNE Control2CheckDone
  ;if we do, set it in motion
  LDA #$00
  STA ballState
  LDA #$01
  STA ballDirX
  STA ballXspeed
  LDA random
  AND #%00000001
  STA ballDirY
  ;make paddle2 immune to collision
  LDA #$01
  STA canCollide
Control2CheckDone:
  RTS

;(SUB)  
ControlAI:
  LDA ballSpeed
  CMP #$01
  BNE SpeedOk
  CLC
  ADC #$01
SpeedOk:  
  STA $FD
  LDA ballState
  SEC
  SBC #$02
  BNE AIownershipCheckDone
  ;if we do, set it in motion
  DEC aiWaitFrame
  BNE AImoveDone
  LDA #$60
  STA aiWaitFrame
  LDA #$00
  STA ballState
  LDA #$01
  STA ballDirX
  STA ballXspeed
  LDA random
  AND #%00000001
  STA ballDirY
  ;make paddle2 immune to collision
  LDA #$01
  STA canCollide
  JMP AImoveDone
AIownershipCheckDone:
  LDA BALL_Y
  CLC 
  ADC #$04
  STA $FE
  LDA paddle2
  CLC
  ADC #$10
  CMP $FE
  BCS AImoveUp
  ;move down, check if size is large enough first
  STA $FF
  LDA $FE
  SEC
  SBC $FF
  CMP #$03
  BCC AImoveDone
  LDA paddle2
  CLC 
  ADC $FD
  STA paddle2
  JMP AImoveDone
AImoveUp:
  ;move up, check if size is large enough first
  SEC
  SBC $FE
  CMP #$03
  BCC AImoveDone
  LDA paddle2
  SEC
  SBC $FD
  STA paddle2
AImoveDone:  
  RTS
  
;(SUB)
PaddleCollisionDetection:
  ;paddle 1 too high
  LDA #WALL_TOP
  SEC
  SBC paddle1
  BCC Paddle1NotTooHigh
  LDA #WALL_TOP
  STA paddle1
Paddle1NotTooHigh:
  ;paddle1 too low
  LDA paddle1
  CLC
  ADC #PADDLE_HEIGHT
  SEC
  SBC #WALL_BOTTOM
  BCC Paddle1NotTooLow
  LDA #WALL_BOTTOM
  SEC
  SBC #PADDLE_HEIGHT
  STA paddle1
Paddle1NotTooLow:
  ;paddle 2 too high
  LDA #WALL_TOP
  SEC
  SBC paddle2
  BCC Paddle2NotTooHigh
  LDA #WALL_TOP
  STA paddle2
Paddle2NotTooHigh:
  ;paddle1 too low
  LDA paddle2
  CLC
  ADC #PADDLE_HEIGHT
  SEC
  SBC #WALL_BOTTOM
  BCC Paddle2NotTooLow
  LDA #WALL_BOTTOM
  SEC
  SBC #PADDLE_HEIGHT
  STA paddle2
Paddle2NotTooLow:   
  RTS
  
;(SUB)
SetPaddlePositions:
  LDA paddle1
  LDX #$04
  LDY #$00  
Paddle1PositionLoop: 
  STA BALL_Y, X
  CLC
  ADC #$08 
  INX
  INX
  INX
  INX
  INY
  CPY #$04
  BNE Paddle1PositionLoop
  
  LDA paddle2
  LDY #$00  
Paddle2PositionLoop:
  STA BALL_Y, X
  CLC
  ADC #$08 
  INX
  INX
  INX
  INX
  INY
  CPY #$04
  BNE Paddle2PositionLoop
  RTS
  
;(SUB)  
UpdateScores:
  LDA #$20
  STA $2006
  LDA #$21
  STA $2006
  LDA score1
  STA $2007
  
  LDA #$20
  STA $2006
  LDA #$3E
  STA $2006
  LDA score2
  STA $2007
 
  LDA #$00 
  STA $2005 
  STA $2005
  
  LDA score1
  CMP #WINNING_SCORE
  BNE Player1ScoreChecked
  JSR LoadStateWinScreen
Player1ScoreChecked:
  LDA score2
  CMP #WINNING_SCORE
  BNE ScoresUpdated
  JSR LoadStateWinScreen
ScoresUpdated:  
  RTS
  
;initialise game variables
;(SUB)
InitialSetup:
  LDA #$00
  STA score1
  STA score2
  STA ballXspeed
  STA ballYspeed
  STA ballDirX
  STA ballDirY
  STA canCollide
  LDA #$01 ;01 is ingame, 00 is titlescreen, 02 is winscreen
  STA ballSpeed
  STA gameState
  STA ballState
  LDA #$30
  STA menuWait
  LDA #$60
  STA paddle1
  STA paddle2
  STA aiWaitFrame
  RTS
  
HandleInputEnd:
  LDA controller1
  BEQ NoInputs
  LDA #$00
  STA gameState
  STA numPlayers
  JSR LoadStateMainMenu
NoInputs:
  RTS
  
HandleInputMenu:
  LDA menuWait
  BEQ MenuDoneWaiting
  DEC menuWait
  RTS
MenuDoneWaiting:
  LDA controller1
  AND #%00010000
  BEQ MenuInputDown
  JSR PlayBeep2
  JSR LoadStateInGame
MenuInputDown:
  LDA controller1
  AND #%00000100
  BEQ MenuInputUp
  LDA numPlayers
  CMP #$01
  BEQ MenuInputDone
  ;switch to 2 players
  JSR PlayBeep1
  LDA #$01
  STA numPlayers
  LDA #$22 ;change bg graphics
  STA $2006
  LDA #$4A
  STA $2006
  LDA #$24
  STA $2007
 
  LDA #$22
  STA $2006
  LDA #$8A
  STA $2006
  LDA #$D7
  STA $2007
  
  LDA #$00 
  STA $2005 
  STA $2005
MenuInputUp:  
  LDA controller1
  AND #%00001000
  BEQ MenuInputDone
  LDA numPlayers
  BEQ MenuInputDone
  ;switch to 1 player
  JSR PlayBeep1
  LDA #$00
  STA numPlayers
  LDA #$22 ;change bg graphics
  STA $2006
  LDA #$4A
  STA $2006
  LDA #$D7
  STA $2007
 
  LDA #$22
  STA $2006
  LDA #$8A
  STA $2006
  LDA #$24
  STA $2007
  
  LDA #$00 
  STA $2005 
  STA $2005
MenuInputDone:
  RTS  
  
GoalScore:
  LDA canCollide
  SEC
  SBC #$01
  BEQ GoalPlayer2
  INC score1
  LDA #$02
  STA ballState
  JMP PlayerScoreAdjusted
GoalPlayer2:
  INC score2
  LDA #$01
  STA ballState
PlayerScoreAdjusted:  
  JSR UpdateScores
  LDA #$01
  STA ballSpeed
  STA ballXspeed
  STA ballYspeed
  LDA #$00
  STA numBounces
  RTS
  
;(SUB)
PlayBeep1:
  LDA #%10011010
  STA $4000
  LDA #$E0
  STA $4002
  LDA #%10000000
  STA $4003
  RTS  
  
;(SUB)
PlayBeep2:
  LDA #%10011010
  STA $4000
  LDA #$44
  STA $4002
  LDA #%10000000
  STA $4003
  RTS  

;(SUB)
PlayBeep3:
  LDA ballState
  BNE Sound3Done ;total hack, I don't really care
  LDA #%10011010
  STA $4000
  LDA #$E0
  STA $4002
  LDA #%10000000
  STA $4003
Sound3Done:  
  RTS    
  
;(SUB)  
vblankwait:       ; First wait for vblank to make sure PPU is ready
  BIT $2002
  BPL vblankwait
  RTS
  
;(SUB)  
LoadStateMainMenu:
  LDA #$00
  LDA #$00
  STA $2000
  STA $2001
  
  LDA $2002
  LDA #$20
  STA $2006
  LDA #$00
  STA $2006
  LDX #$00
  ;background is 960 bytes, 32 * 30 tiles
  ;title goes on row 10
  LDX #$00 ;first 8 rows
LoadBackgroundMenuLoop1:
  LDA #$24
  STA $2007
  INX
  CPX #$00
  BNE LoadBackgroundMenuLoop1
  
  ;9th row
LoadBackgroundMenuLoop2:
  LDA #$24
  STA $2007
  INX
  CPX #$20
  BNE LoadBackgroundMenuLoop2
  
  ;10th row, title
  LDX #$00
LoadBackgroundMenuLoop3:
  LDA titleText, X
  STA $2007
  INX
  CPX #$20
  BNE LoadBackgroundMenuLoop3
  
  ;rows 11 - 18
  LDX #$00
LoadBackgroundMenuLoop4:
  LDA #$24
  STA $2007
  INX
  CPX #$00
  BNE LoadBackgroundMenuLoop4

  ;rows 19 - 21
  LDX #$00
LoadBackgroundMenuLoop5:
  LDA menuText, X
  STA $2007
  INX
  CPX #$60
  BNE LoadBackgroundMenuLoop5
  
  ;rows 22 - 29
  LDX #$00
LoadBackgroundMenuLoop6:
  LDA #$24
  STA $2007
  INX
  CPX #$00
  BNE LoadBackgroundMenuLoop6  
  
  ;rows 30-32
  LDX #$00
LoadBackgroundMenuLoop7:
  LDA #$24
  STA $2007
  INX
  CPX #$60
  BNE LoadBackgroundMenuLoop7  
  
  LDA $2002
  LDA #$23
  STA $2006
  LDA #$C0
  STA $2006
  LDX #$00
LoadAttributeLoopMenu:
  LDA attribute, X
  STA $2007
  INX
  CPX #$40
  BNE LoadAttributeLoopMenu
  
  LDA #$00
  STA $2005
  STA $2005
  
  LDA #%10010000   ; enable NMI, sprites from Pattern Table 0
  STA $2000

  LDA #%00001110   ; enable background, no sprites
  STA $2001
  
  LDA $DE
  RTS
  
LoadStateWinScreen:
  LDA #$00
  STA $2000
  STA $2001
  
  LDA $2002
  LDA #$20
  STA $2006
  LDA #$00
  STA $2006
  LDX #$00
  ;background is 960 bytes, 32 * 30 tiles
  LDX #$00 ;first 8 rows
LoadBackgroundEndLoop1:
  LDA #$24
  STA $2007
  INX
  CPX #$00
  BNE LoadBackgroundEndLoop1
  ;9-14
  LDX #$00
LoadBackgroundEndLoop2:
  LDA #$24
  STA $2007
  INX
  CPX #$C0
  BNE LoadBackgroundEndLoop2
  ;15th row, win message
  LDX #$00
LoadBackgroundEndLoop3:
  LDA winText, X
  STA $2007
  INX
  CPX #$20
  BNE LoadBackgroundEndLoop3
  ;16-23
  LDX #$00
LoadBackgroundEndLoop4:
  LDA #$24
  STA $2007
  INX
  CPX #$00
  BNE LoadBackgroundEndLoop4
  ;24th row
  LDX #$00
LoadBackgroundEndLoop5:
  LDA rngText, X
  STA $2007
  INX
  CPX #$20
  BNE LoadBackgroundEndLoop5
  ;25-30
  LDX #$00
LoadBackgroundEndLoop6:
  LDA #$24
  STA $2007
  INX
  CPX #$C0
  BNE LoadBackgroundEndLoop6
  
  ;write 2 instead of 1 in event player2 has won
  LDA score2
  CMP #WINNING_SCORE
  BNE Player2NotWon
  LDA #$21
  STA $2006
  LDA #$D0
  STA $2006
  LDA #$02
  STA $2007
Player2NotWon:
  LDA #$00
  STA $2005
  STA $2005
  
  LDA #%10010000   ; enable NMI, sprites from Pattern Table 0
  STA $2000

  LDA #%00001110   ; enable background, no sprites
  STA $2001
  
  LDA #$02
  STA gameState
  RTS  

LoadStateInGame:
  LDA #$00
  STA $2000
  STA $2001
  JSR InitialSetup
  
  LDA $2002
  LDA #$20
  STA $2006
  LDA #$00
  STA $2006
  LDX #$00
LoadBackgroundLoop1:
  LDA nametable1, X
  STA $2007
  INX
  CPX #$00
  BNE LoadBackgroundLoop1
LoadBackgroundLoop2:
  LDA nametable2, X
  STA $2007
  INX
  CPX #$00
  BNE LoadBackgroundLoop2
LoadBackgroundLoop3:
  LDA nametable3, X
  STA $2007
  INX
  CPX #$00
  BNE LoadBackgroundLoop3
LoadBackgroundLoop4: ; Last loop only runs 192 times to not run into
  LDA nametable4, X ; attribute table space
  STA $2007
  INX
  CPX #$C0
  BNE LoadBackgroundLoop4
  
LoadAttribute:
  LDA $2002
  LDA #$23
  STA $2006
  LDA #$C0
  STA $2006
  LDX #$00
LoadAttributeLoop:
  LDA attribute, X
  STA $2007
  INX
  CPX #$40
  BNE LoadAttributeLoop
  
  LDA #$00
  STA $2005
  STA $2005
  
  LDA #%10010000   ; enable NMI, sprites from Pattern Table 0
  STA $2000

  LDA #%00011110   ; enable sprites, background etc.
  STA $2001
  RTS  
;;;;;;;;;;;;;;  
  
  .bank 1
  .org $E000
palette:
  ;bg palette 
  .db $0F,$31,$32,$33,$0F,$30,$30,$30,$0F,$39,$3A,$3B,$0F,$3D,$3E,$0F
  ;sprite palette
  .db $0F,$30,$20,$10,$0F,$30,$30,$30,$0F,$1C,$15,$14,$0F,$02,$38,$3C
  
winText:
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$19,$15,$0A,$22,$0E,$1B,$24 
  .db $01,$24,$20,$12,$17,$1C,$2B,$24,$24,$24,$24,$24,$24,$24,$24,$24 
  
rngText:
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$10,$0A,$16,$0E,$24
  .db $0B,$22,$24,$0D,$11,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24 

titleText:
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$1D,$0E,$17,$17,$12,$1C,$24
  .db $0F,$18,$1B,$24,$01,$00,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

menuText:
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$D7,$24,$01,$24,$19,$15
  .db $0A,$22,$0E,$1B,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$02,$24,$19,$15
  .db $0A,$22,$0E,$1B,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  
sprites: 
     ;y,tile,attr,x
  .db $00,$75,$01,$00 ;ball 
  .db $00,$86,$01,$08 ;left_paddle_top 
  .db $00,$86,$01,$08 ;left_paddle_middle1
  .db $00,$86,$01,$08 ;left_paddle_middle2 
  .db $00,$86,$01,$08 ;left_paddle_bottom
  .db $00,$86,$01,$F0 ;right_paddle_top 
  .db $00,$86,$01,$F0 ;right_paddle_middle1
  .db $00,$86,$01,$F0 ;right_paddle_middle2
  .db $00,$86,$01,$F0 ;right_paddle_bottom
  
nametable1: ;backgrounds
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 1
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$00,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 2
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$00,$24  

  .db $25,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7  ;;row 3
  .db $D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$26  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$25  ;;row 4
  .db $26,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  
  
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 5
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$25  ;;row 6
  .db $26,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24 

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 7
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$25  ;;row 8
  .db $26,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  
  
nametable2: ;backgrounds
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 1
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$25  ;;row 8
  .db $26,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 1
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$25  ;;row 8
  .db $26,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  
  
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 1
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$25  ;;row 8
  .db $26,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 1
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$25  ;;row 8
  .db $26,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

nametable3: ;backgrounds
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 1
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$25  ;;row 8
  .db $26,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 1
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$25  ;;row 8
  .db $26,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  
  
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 1
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$25  ;;row 8
  .db $26,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 1
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$25  ;;row 8
  .db $26,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  
  
nametable4: ;backgrounds
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 1
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$25  ;;row 8
  .db $26,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 1
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $25,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7  ;;row 3
  .db $D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$D7,$26  
  
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 1
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  

  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  ;;row 1
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24  
  
attribute:
  .db %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101
  .db %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101
  .db %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101
  .db %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101
  .db %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101
  .db %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101
  .db %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101
  .db %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101
  
  .org $FFFA     ;start interrupt vectors here
  .dw NMI        ;jump to NMI on vblank
  .dw RESET      
  .dw 0          ;turn off external interrupt IRQ
  
;;;;;;;;;;;;;;  
  
  .bank 2
  .org $0000
  .incbin "sprites.chr"   ;includes 8KB graphics file