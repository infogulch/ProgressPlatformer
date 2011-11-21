#NoEnv
#SingleInstance Force

    TargetFrameRate := 100
    
    global Gravity := 981
    global Friction := .01
    global Restitution := 0.6
    
    global Level, LevelIndex := 1
    global Left, Right, Jump, Duck, Health
    
    global GameGui
    DeltaLimit := 0.015
    
    SetBatchLines, -1
    SetWinDelay, -1
    
    GoSub MakeGuis
    
    TargetFrameDelay := 1000 / TargetFrameRate
    TickFrequency := 0, DllCall("QueryPerformanceFrequency","Int64*",TickFrequency) ;obtain ticks per second
    PreviousTicks := 0, CurrentTicks := 0
    Loop
    {
        If Initialize()
            Break
        DllCall("QueryPerformanceCounter","Int64*",PreviousTicks)
        Loop
        {
            DllCall("QueryPerformanceCounter","Int64*",CurrentTicks)
            Delta := Round((CurrentTicks - PreviousTicks) / TickFrequency,4)
            DllCall("QueryPerformanceCounter","Int64*",PreviousTicks)
            If (Delta > DeltaLimit)
                Delta := DeltaLimit
            Sleep, % Round(TargetFrameDelay - (Delta * 1000))
            If Step(Delta)
                Break
        }
    }
    MsgBox, Game complete!
ExitApp

#if WinActive("ahk_id" GameGui.hwnd)

f::
    GuiControl, % "Show" (ShowFrameRate := !ShowFrameRate), FrameRate
    SetTimer, ShowFrameRate, % ShowFrameRate ? 200 : "Off"
return

ShowFrameRate:
    GuiControl, , FrameRate, % Round(1 / Delta)
return

MakeGuis:
    ;create game window
    Gui, Color, Black
    Gui, Add, Edit, vFrameRate w40 x0 y0 hidden backgroundblack
    Gui, +OwnDialogs +LastFound

    GameGUI := {}
    GameGUI.hwnd := WinExist()
    GameGUI.Count := {}
    GameGUI.Count.BlockRectangle  := 0
    GameGUI.Count.PlayerRectangle := 0
    GameGUI.Count.GoalRectangle   := 0
    GameGUI.Count.EnemyRectangle  := 0
Return

GuiEscape:
GuiClose:
ExitApp

Initialize() 
{
    Health := 100

    LevelFile := A_ScriptDir . "\Levels\Level " . LevelIndex . ".txt"
    If !FileExist(LevelFile)
        Return, 1
    FileRead, LevelDefinition, %LevelFile%
    If ErrorLevel
        Return, 1

    ;hide all controls
    If ObjHasKey(Level,"Blocks")
    {
        For Index In Level.Blocks
            GuiControl, Hide, LevelRectangle%Index%
    }
    If ObjHasKey(Level,"Platforms")
    {
        For Index In Level.Platforms
            GuiControl, Hide, PlatformRectangle%Index%
    }
    If ObjHasKey(Level,"Player")
        GuiControl, Hide, PlayerRectangle
    If ObjHasKey(Level,"Goal")
        GuiControl, Hide, GoalRectangle
    If ObjHasKey(Level,"Enemies")
    {
        For Index, Rectangle In Level.Enemies
            GuiControl, Hide, EnemyRectangle%Index%
    }

    Level := ParseLevel(LevelDefinition)

    PreventRedraw(GameGui.hwnd)

    For Name, Count In GameGUI.Count
    {
        Loop, %Count%
            GuiControl, Hide, %Name%%A_Index%
    }
    
    Gui, +LastFound
    hWindow := WinExist()
    PreventRedraw(hWindow)
    
    ;create level
    For Index, Rectangle In Level.Blocks
        PlaceRectangle(Rectangle.X,Rectangle.Y,Rectangle.W,Rectangle.H,"LevelRectangle",Index,"BackgroundRed")

    ;create platforms
    For Index, Rectangle In Level.Platforms
        PlaceRectangle(Rectangle.X,Rectangle.Y,Rectangle.W,Rectangle.H,"PlatformRectangle",Index,"BackgroundLime")

    ;create player
    PlaceRectangle(Level.Player.X,Level.Player.Y,Level.Player.W,Level.Player.H,"PlayerRectangle","","-Smooth Vertical")

    ;create goal
    PlaceRectangle(Level.Goal.X,Level.Goal.Y,Level.Goal.W,Level.Goal.H,"GoalRectangle","","BackgroundWhite")

    ;create enemies
    For Index, Rectangle In Level.Enemies
        PlaceRectangle(Rectangle.X,Rectangle.Y,Rectangle.W,Rectangle.H,"EnemyRectangle",Index,"BackgroundBlue")

    AllowRedraw(hWindow)
    WinSet, Redraw

    Gui, Show, % "W" Level.Width " H" Level.Height, ProgressPlatformer
    
    WinGetPos,,, Width, Height, % "ahk_id" GameGui.hwnd
    GameGui.Width := Width
    GameGui.Height := Height
}

PlaceRectangle(X,Y,W,H,Name,Index = "",Options = "")
{
    global
    static NameCount := Object()
    local hWnd
    If !ObjHasKey(NameCount,Name)
        NameCount[Name] := 0
    If ((Index = "" && NameCount[Name] = 0) || NameCount[Name] < Index) ;control does not yet exist
    {
        NameCount[Name]++
        Gui, Add, Progress, x%X% y%Y% w%W% h%H% v%Name%%Index% %Options% hwndhwnd, 0
        Control, ExStyle, -0x20000, , ahk_id%hwnd% ;remove WS_EX_STATICEDGE extended style
    }
    Else
    {
        GuiControl, Show, %Name%%Index%
        GuiControl, Move, %Name%%Index%, x%X% y%Y% w%W% h%H%
    }
}

PreventRedraw(hWnd)
{
    DetectHidden := A_DetectHiddenWindows
    DetectHiddenWindows, On
    SendMessage, 0xB, 0, 0,, ahk_id %hWnd% ;WM_SETREDRAW
    DetectHiddenWindows, %DetectHidden%
}

AllowRedraw(hWnd)
{
    DetectHidden := A_DetectHiddenWindows
    DetectHiddenWindows, On
    SendMessage, 0xB, 1, 0,, ahk_id %hWnd% ;WM_SETREDRAW
    DetectHiddenWindows, %DetectHidden%
}

Step(Delta)
{
    If !WinActive("ahk_id" GameGui.hwnd)
        return 0
    If GetKeyState("Tab","P") ;slow motion
        Delta *= 0.3
    If Input()
        Return, 1
    If Physics(Delta)
        Return, 2
    If Logic(Delta)
        Return, 3
    If Update()
        Return, 4
    Return, 0
}

Input()
{
    Duck  := GetKeyState("Down","P")  || GetKeyState("S", "P")
    Jump  := GetKeyState("Up","P")    || GetKeyState("W", "P")
    Left  := GetKeyState("Left","P")  || GetKeyState("A", "P")
    Right := GetKeyState("Right","P") || GetKeyState("D", "P")
    Return, 0
}

Physics(Delta)
{
    ; O(2N + N*(N + K)) N: entities, K: blocks
    local entity
    
    ; apply changes in speeds from last frame to position
    for i, entity in Level.Entities
    {
        entity.X += delta * entity.Speed.X
        entity.Y += delta * entity.Speed.Y
    }
    
    ; start physics for this frame
    for i, entity in Level.Entities
        entity.physics(delta)
    
    ; apply newspeed to speed
    for i, entity in Level.Entities
    {
        entity.Speed.X := entity.NewSpeed.X + entity.MoveX * entity.MoveSpeed * Delta
        entity.Speed.Y := entity.NewSpeed.Y
    }
}

Logic(Delta)
{
    For Index, Entity in Level.Entities
        Entity.Logic(Delta)
}

Update()
{
    global
    local Rectangle, Index
    GuiControl,, PlayerRectangle, %Health%
    ;update everything
    For Index, Rectangle In Level.Rectangles
        GuiControl, Move, % Rectangle.Type, % "x" . Rectangle.X . " y" . Rectangle.Y . " w" . Rectangle.W . " h" . Rectangle.H
    Return, 0
}

ParseLevel(LevelDefinition)
{
    ; Object/Level Heirarchy:
    ; 
    ; Rectangles: Everything collide-able
    ;   Blocks: fixed rectangle
    ;   Entities: movable rectangle
    ;       Player: player-controlled entity
    ;       Enemies: AI-controlled entity
    ; 
    local Level := Object()
    LevelDefinition := RegExReplace(LevelDefinition,"S)#[^\r\n]*")
    
    Level.Rectangles := []
    Level.Blocks     := []
    Level.Entities   := []
    Level.Enemies    := []
    Level.Platforms := []
    
    If RegExMatch(LevelDefinition,"iS)Blocks\s*:\s*\K(?:\d+\s*(?:,\s*\d+\s*){3})*",Property)
    {
        StringReplace, Property, Property, `r,, All
        StringReplace, Property, Property, %A_Space%,, All
        StringReplace, Property, Property, %A_Tab%,, All
        While, InStr(Property,"`n`n")
            StringReplace, Property, Property, `n`n, `n, All
        Property := Trim(Property,"`n")
        Loop, Parse, Property, `n
        {
            StringSplit, Entry, A_LoopField, `,, %A_Space%`t
            rect := new _Rectangle(Entry1,Entry2,Entry3,Entry4)
            rect.Type :=  "BlockRectangle" A_Index
            rect.Indices := {}
            Level.Blocks.Insert(rect)    , rect.Indices.Blocks     := Level.Blocks.MaxIndex()
            Level.Rectangles.Insert(rect), rect.Indices.Rectangles := Level.Rectangles.MaxIndex()
        }
    }
    If RegExMatch(LevelDefinition,"iS)Platforms\s*:\s*\K(?:\d+\s*(?:,\s*\d+\s*){4,7})*",Property)
    {
        StringReplace, Property, Property, `r,, All
        StringReplace, Property, Property, %A_Space%,, All
        StringReplace, Property, Property, %A_Tab%,, All
        While, InStr(Property,"`n`n")
            StringReplace, Property, Property, `n`n, `n, All
        Property := Trim(Property,"`n")
        Loop, Parse, Property, `n
        {
            Entry6 := 0, Entry7 := 100
            StringSplit, Entry, A_LoopField, `,, %A_Space%`t
            ObjInsert(Level.Platforms,new _Platform(Entry1,Entry2,Entry3,Entry4,Entry5,Entry6,Entry7))
        }
    }
    If RegExMatch(LevelDefinition,"iS)Player\s*:\s*\K(?:\d+\s*(?:,\s*\d+\s*){3,5})*",Property)
    {
        Entry5 := 0, Entry6 := 0
        StringSplit, Entry, Property, `,, %A_Space%`t`r`n
        
        player := new _Player(Entry1,Entry2,Entry3,Entry4,Entry5,Entry6)
        player.Type := "PlayerRectangle"
        Level.Player := player
        player.Indices := {}
        Level.Rectangles.insert(player), player.Indices.Rectangles := Level.Rectangles.MaxIndex()
        Level.Entities.insert(player)  , player.Indices.Entities   := Level.Entities.MaxIndex()
    }
    
    If RegExMatch(LevelDefinition,"iS)Goal\s*:\s*\K(?:\d+\s*(?:,\s*\d+\s*){3})*",Property)
    {
        StringSplit, Entry, Property, `,, %A_Space%`t`r`n
        Level.Goal := new _Rectangle(Entry1,Entry2,Entry3,Entry4)
        ; the goal is handled specially and not used for collisions, so omit from Level.Rectangles
    }
    
    If RegExMatch(LevelDefinition,"iS)Enemies\s*:\s*\K(?:\d+\s*(?:,\s*\d+\s*){3,5})*",Property)
    {
        StringReplace, Property, Property, `r,, All
        StringReplace, Property, Property, %A_Space%,, All
        StringReplace, Property, Property, %A_Tab%,, All
        While, InStr(Property,"`n`n")
            StringReplace, Property, Property, `n`n, `n, All
        Property := Trim(Property,"`n")
        Loop, Parse, Property, `n, `r `t
        {
            Entry5 := 0, Entry6 := 0
            StringSplit, Entry, A_LoopField, `,, %A_Space%`t
            
            enemy := new _Enemy(Entry1,Entry2,Entry3,Entry4,Entry5,Entry6)
            enemy.Type := "EnemyRectangle" A_Index
            enemy.Indices := {}
            Level.Enemies.insert(enemy)   , enemy.Indices.Enemies    := Level.Enemies.MaxIndex()
            Level.Rectangles.insert(enemy), enemy.Indices.Rectangles := Level.Rectangles.MaxIndex()
            Level.Entities.insert(enemy)  , enemy.Indices.Entities   := Level.Entities.MaxIndex()
        }
    }
    
    Level.Width := 0
    Level.Height := 0
    for i, Rectangle in Level.Rectangles
    {
        if (Rectangle.X + Rectangle.W > Level.Width)
            Level.Width := Rectangle.X + Rectangle.W
        if (Rectangle.Y + Rectangle.H > Level.Height)
            Level.Height := Rectangle.Y + Rectangle.H
    }
    Level.Width += 10
    Level.Height += 10
    Return, Level
}

class _Rectangle
{
    __new(X,Y,W,H)
    {
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        this.fixed := true
        this.Speed := { X: 0, Y: 0 }
    }
    
    Center()
    {
        Return, { X: this.X + (this.W / 2),Y: this.Y + (this.H / 2) }
    }
    
    ; Distance between the *centers* of two blocks
    CenterDistance(Rectangle)
    {
        a := this.Center()
        b := Rectangle.Center()
        Return, Sqrt((a.X - b.X) ** 2 + (a.Y - b.Y) ** 2)
    }
    
    ; calculates the closest distance between two blocks (*not* the centers)
    Distance(Rectangle)
    {
        X := this.IntersectsX(Rectangle) ? 0 : min(Abs(this.X - (Rectangle.X + Rectangle.W)),Abs(Rectangle.X - (this.X + this.W)))
        Y := this.IntersectsY(Rectangle) ? 0 : min(Abs(this.Y - (Rectangle.Y + Rectangle.H)),Abs(Rectangle.Y - (this.Y + this.H)))
        Return, Sqrt((X ** 2) + (Y ** 2))
    }
    
    ; Returns true if this is completely inside Rectangle
    Inside(Rectangle)
    {
        Return, (this.X >= Rectangle.X) && (this.Y >= Rectangle.Y) && (this.X + this.W <= Rectangle.X + Rectangle.W) && (this.Y + this.H <= Rectangle.Y + Rectangle.H)
    }
    
    ; returns the amount of intersection or 0
    IntersectsX( rect ) {
        return IntersectN(this.X, this.W, rect.X, rect.W)
    }
    
    IntersectsY( rect ) {
        return IntersectN(this.Y, this.H, rect.Y, rect.H)
    }
}

class _Entity extends _Rectangle {
    __new( X, Y, W, H, SpeedX = 0, SpeedY = 0) {
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        this.mass := W * H ; * density
        this.fixed := false
        
        this.JumpSpeed := 300
        
        this.Seeking := false
        
        this.EnemyX := this.EnemyY := 0
        this.Intersect := { X: 0, Y: 0 }
        
        this.NewSpeed := {}
        this.Speed := { X: SpeedX, Y: SpeedY }
    }
    
    Physics( delta ) {
        this.NewSpeed.Y := this.Speed.Y + Gravity * delta
        this.NewSpeed.X := this.Speed.X
        
        if InStr(this.type, "player")
            this.EnemyX := 0, this.EnemyY := 0
        this.Intersect.X := 0
        this.Intersect.Y := 0
        
        for i, rect in Level.Rectangles
        {
            if (this == rect)
                continue
            
            X := this.IntersectsX(rect)
            Y := this.IntersectsY(rect)
            
            if (X == "" || Y == "")
                continue
            
            if !(Abs(X) < Abs(Y))
            {   ; collision along horizontal
                this.Y += Y ;move out of intersection
                this.Intersect.Y := Y
                this.Friction(Delta, rect, "X")
                
                if (this.Y > rect.Y && this.WantJump && rect.fixed) ; ceiling stick, no net effect if it's a movable rect
                    this.NewSpeed.Y -= Gravity * Delta
                    , this.NewSpeed.Y *= 0.1
                else {
                    if (this.Y < rect.Y && this.WantJump) ; jump: increase speed *down* and let .Impact() handle the effects on other rects
                        this.NewSpeed.Y += this.JumpSpeed
                    this.Impact(Delta, rect, "Y")
                }
                if InStr(this.type, "player") && InStr(rect.type, "enemy") && this.EnemyY == 0
                    this.EnemyY := i * Sign(Y)
            }
            else
            {   ; collision along vertical
                this.X += X
                this.Intersect.X := X
                this.Friction(Delta, rect, "Y")
                this.Impact(Delta, rect, "X")
                
                if (Sign(X) == -this.MoveX) ; wall climb
                {
                    this.NewSpeed.Y -= Gravity * Delta + this.MoveSpeed * Delta * this.WantJump
                    if rect.fixed
                        this.NewSpeed.X *= 0.01
                    else
                        rect.Speed.Y += (Gravity * Delta + this.MoveSpeed * Delta * this.WantJump) * this.mass / rect.mass
                }
                if InStr(this.type, "player")
                {
                    if InStr(rect.type, "enemy")
                        this.EnemyX := True
                }
            }
        }
    }
    
    Impact( delta, rect, dir ) {
        if rect.fixed
            this.NewSpeed[dir] *= -Restitution ; / 2 if button is pressed in same direction of Speed[dir]
        else
            this.NewSpeed[dir] := (this.mass*this.NewSpeed[dir] + rect.mass*(rect.Speed[dir] + Restitution*(rect.Speed[dir] - this.NewSpeed[dir])))/(this.mass + rect.mass)
            ; formula slightly modified from: http://en.wikipedia.org/wiki/Coefficient_of_restitution#Speeds_after_impact
    }
    
    Friction( delta, rect, dir ) { ; not sure this is 100% right. 
        ; dir: direction of motion
        ; normal: direction normal to motion
        ; normal := dir = "Y" ? "X" : "Y" 
        ; this.NewSpeed[dir] -= min(this.Speed[dir], Friction * (this.NewSpeed[normal] - this.Speed[normal]) / delta * this.mass)
        this.NewSpeed[dir] *= Friction ** delta
    }
}

class _Player extends _Entity {
    __new( X, Y, W, H, SpeedX = 0, SpeedY = 0) {
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        
        this.mass := W * H * 1.5
        this.fixed := false
        this.padding := 100
        
        this.JumpSpeed := 300
        this.MoveSpeed := 800
        this.MoveX := 0
        
        this.EnemyX := this.EnemyY := 0
        this.Intersect := { X: 0, Y: 0 }
        
        this.NewSpeed := { X: SpeedX, Y: SpeedY }
        this.Speed := { X: SpeedX, Y: SpeedY }
    }
    
    Logic(Delta) {
        If (this.X < -this.Padding || this.X > (Level.Width + this.Padding) || this.Y > (Level.Height + this.Padding)) ;out of bounds
            Return, 1
        If (Health <= 0) ;out of health
            Return, 2
        If this.Inside(Level.Goal) ;reached goal
        {
            Score := Round(Health)
            MsgBox, You win!`n`nYour score was %Score%.
            LevelIndex++ ;move to the next level
            Return, 3
        }
        this.WantJump := Jump
        
        this.MoveX := Left ? -1 : Right ? 1 : 0
        
        this.H := Duck ? 30 : 40
        
        ; health/enemy killing
        If (this.EnemyX || this.EnemyY > 0)
            Health -= 200 * Delta
        Else If this.EnemyY
        {
            enemy1 := Level.Rectangles.Remove(Abs(this.EnemyY),"")
            enemy2 := Level.Enemies.Remove(enemy1.indices.enemies,"")
            enemy3 := Level.Entities.Remove(enemy1.indices.entities,"")
            GuiControl, Hide, % "EnemyRectangle" enemy1.indices.enemies
            Health += 50
        }
        Return, 0
}
}

class _Enemy extends _Entity {
    __new( X, Y, W, H, SpeedX = 0, SpeedY = 0) {
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        
        this.mass := W * H ; * density
        this.fixed := false
        
        this.JumpSpeed := 270
        this.MoveSpeed := 600
        this.MoveX := 0
        this.SeekDistance := 120
        
        this.Seeking := false
        
        this.Intersect := { X: 0, Y: 0 }
        
        this.NewSpeed := { X: SpeedX, Y: SpeedY }
        this.Speed := { X: SpeedX, Y: SpeedY }
    }
    
    Logic(Delta) {
        if this.Seeking || Level.Player.Distance(this) < this.SeekDistance 
        {
            this.Seeking := True
            this.WantJump := this.Y >= Level.Player.Y
            this.MoveX := Sign(Level.Player.center().X - this.center().X)
        }
    }
}

class _Block extends _Rectangle {
    __new(X,Y,W,H)
    {
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        this.fixed := true
        this.Speed := { X: 0, Y: 0 }
    }
    
}

Sign( x ) {
    return x == 0 ? 0 : x < 0 ? -1 : 1
}

IntersectN(a1, a2, b1, b2) {
    ; 1's are points, 2's are distances. to change both to points, take out the "\+[ab]1" parts from the min() expression
    ; returns a nonzero integer if they intersect, 0 if they just touch, and "" if they do not intersect
    ; positive if a > b
    sub := b1 > a1 ? b1 : a1 ; max
    a := a2 + a1 - sub
    b := b2 + b1 - sub
    r := b < a ? b : a ; min
    return r >= 0 ? r * (a1 + a2/2 < b1 + b2/2 ? -1 : 1) : ""
}

min( x* ) {
    ; accepts either an array or args
    if (ObjMaxIndex(x) == 1 && IsObject(x[1]))
        x := x[1]
    r := x[1]
    loop % ObjMaxIndex(x)-1
        if (x[A_Index+1] < r)
            r := x[A_Index+1]
    return r
}

max( x* ) {
    ; accepts either an array or args
    if (ObjMaxIndex(x) == 1 && IsObject(x[1]))
        x := x[1]
    r := x[1]
    loop % ObjMaxIndex(x)-1
        if (x[A_Index+1] > r)
            r := x[A_Index+1]
    return r
}
