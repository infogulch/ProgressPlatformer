#NoEnv
#SingleInstance Force

    TargetFrameRate := 50
    
    global Gravity := 981
    global Friction := .01
    global Restitution := 0.6
    
    global Level, LevelIndex := 1
    global Left, Right, Jump, Duck, Health
    
    global GameGui
    
    global LOG, DEBUG := False
    OnExit QuitGame
    
    DeltaLimit := 0.05
    
    SetBatchLines, -1
    SetWinDelay, -1
    
    GoSub MakeGuis
    
    DeltaList := []
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
            Delta := (CurrentTicks - PreviousTicks) / TickFrequency
            PreviousTicks := CurrentTicks
            If (Delta > DeltaLimit)
                Delta := DeltaLimit
            if ShowFrameRate
                DeltaList.Insert(1, Delta)
                , DeltaList.Remove(TargetFrameRate)
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
    GuiControl, , FrameRate, % Round(1 / mean(DeltaList))
return

MakeGuis:
    ;create game window
    Gui, Color, Black
    Gui, Font, s14 Cwhite
    Gui, Add, Text, vFrameRate x0 y0 hidden backgroundtrans, 000
    Gui, Font, s10
    Gui, +OwnDialogs +LastFound

    GameGUI := {}
    GameGUI.hwnd := WinExist()
Return

QuitGame:
    if DEBUG
        FileAppend, %LOG%, log.txt
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

    ;hide all rectangles
    For Index, Rectangle In Level.Rectangles
        GuiControl, Hide, % Rectangle.id
    
    ParseLevel(LevelDefinition)
    
    PreventRedraw(GameGui.hwnd)
    
    Gui, +LastFound
    hWindow := WinExist()
    PreventRedraw(hWindow)
    
    ;create platforms
    For Index, Rectangle In Level.Platforms
        PlaceRectangle(Rectangle.X,Rectangle.Y,Rectangle.W,Rectangle.H,"PlatformRectangle",Index,"+Background" Rectangle.Color)
    
    ;create player
    PlaceRectangle(Level.Player.X,Level.Player.Y,Level.Player.W,Level.Player.H,"PlayerRectangle","","-Smooth Vertical")
    
    ;create goal
    PlaceRectangle(Level.Goal.X,Level.Goal.Y,Level.Goal.W,Level.Goal.H,"GoalRectangle","","+BackgroundWhite")
    
    ;create enemies
    For Index, Rectangle In Level.Enemies
        PlaceRectangle(Rectangle.X,Rectangle.Y,Rectangle.W,Rectangle.H,"EnemyRectangle",Index,"+BackgroundBlue")
    
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
    If !NameCount.HasKey(Name)
        NameCount[Name] := 0
    If ((Index = "" && NameCount[Name] = 0) || NameCount[Name] < Index) ;control does not yet exist
    {
        NameCount[Name]++
        Gui, Add, Progress, x%X% y%Y% w%W% h%H% v%Name%%Index% %Options% hwndhwnd, 0
        Control, ExStyle, -0x20000, , ahk_id%hwnd% ;remove WS_EX_STATICEDGE extended style
    }
    Else
    {
        GuiControl, %Options%, %Name%%Index%
        GuiControlGet, hwnd, hwnd, %Name%%Index%
        Control, ExStyle, -0x20000, , ahk_id%hwnd%
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
    Left  := GetKeyState("Left","P")  || GetKeyState("A", "P") ? (Left  ? Left  : A_TickCount) : 0
    Right := GetKeyState("Right","P") || GetKeyState("D", "P") ? (Right ? Right : A_TickCount) : 0
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
        entity.Y += delta * entity.Speed.Y += Gravity * Delta
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
    For Index, Rectangle in Level.Rectangles
        if ret := Rectangle.Logic.(Rectangle, Delta)
            return ret
}

Update()
{
    global
    local Rectangle, Index
    GuiControl,, PlayerRectangle, %Health%
    ;update everything
    For Index, Rectangle In Level.Rectangles
        GuiControl, Move, % Rectangle.id, % "x" . Rectangle.X . " y" . Rectangle.Y . " w" . Rectangle.W . " h" . Rectangle.H
    Return, 0
}

ParseLevel(LevelDefinition)
{
    ; Object Heirarchy:
    ; 
    ; Rectangle: Every object
    ;   Area: Non-collideable Rectangle
    ;   Block: Collide-able Rectangle
    ;       Platform: Block independent from its surroundings, static or dynamic
    ;       Entity: Block that reacts to it's surroundings
    ;           Player: Player-controlled Entity
    ;           Enemy: AI-controlled Entity
    ; 
    
    Level := Object()
    LevelDefinition := RegExReplace(LevelDefinition,"S)#[^\r\n]*")
    
    Level.Rectangles := []
    Level.Areas      := []
    Level.Blocks     := []
    Level.Platforms  := []
    Level.Entities   := []
    Level.Enemies    := []
    
    If RegExMatch(LevelDefinition,"iS)\s*Blocks\s*:\s*\K(?:-?\d+\s*(?:,\s*-?\d+\s*){3,7})*",Property)
    {
        Property := RegExReplace(Property, "(\r?\n){2,}", "$1")
        Loop, Parse, Property, `n
            (new _Platform("PlatformRectangle" A_Index, Split(A_LoopField, ",", " `t`r`n")*))
    }
    If RegExMatch(LevelDefinition,"iS)Player\s*:\s*\K(?:\d+\s*(?:,\s*\d+\s*){3,5})*",Property)
        Level.Player := new _Player("PlayerRectangle", Split(Property, ",", " `t`r`n")*)
    If RegExMatch(LevelDefinition,"iS)Goal\s*:\s*\K(?:\d+\s*(?:,\s*\d+\s*){3})*",Property)
        Level.Goal := new _Area("GoalRectangle", Split(Property, ",", " `t`r`n")*)
    If RegExMatch(LevelDefinition,"iS)Enemies\s*:\s*\K(?:\d+\s*(?:,\s*\d+\s*){3,5})*",Property)
    {
        Property := RegExReplace(Property, "(\r?\n){2,}", "$1")
        Loop, Parse, Property, `n, `r `t
            (new _Enemy("EnemyRectangle" A_Index, Split(A_LoopField, ",", " `t`r`n")*))
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
}


class _Rectangle
{
    LevelAdd()
    {
        Level.Rectangles.Insert(this)
        this.Indices.Rectangles := Level.Rectangles.MaxIndex()
    }
    
    LevelRemove()
    {
        for type, index in this.Indices
            Level[type].remove(index, "")
        GuiControl, Hide, % this.id
        return this
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
    IntersectsX(rect)
    {
        return IntersectN(this.X, this.W, rect.X, rect.W)
    }
    
    IntersectsY(rect)
    {
        return IntersectN(this.Y, this.H, rect.Y, rect.H)
    }
}

class _Area extends _Rectangle
{
    __new(id, X, Y, W, H, LogicCallout = "")
    {
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        this.Logic := LogicCallout
        this.id := id
        this.Speed := { X: 0, Y: 0 }
    }
}

class _Block extends _Rectangle
{
    LevelAdd()
    {
        Level.Blocks.Insert(this)
        this.Indices.Blocks := Level.Blocks.MaxIndex()
        base.LevelAdd()
    }
}

class _Platform extends _Block
{
    __new(id, X, Y, W, H, EndX = "", EndY = "", CSpeed = 0)
    {
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        this.independent := true
        this.Speed := { X: 0, Y: 0 }
        
        this.id := id
        this.Indices := {}
        this.LevelAdd()
        
        if (EndX != "")
        {
            this.Color := "Lime"
            this.Logic := Func("Logic_MovingPlatform")
            this.Start := { X: X, Y: Y }
            this.End := { X: EndX, Y: EndY }
            this.Cycle := CSpeed
            this.Speed.X := (X - EndX) / CSpeed
            this.Speed.Y := (Y - EndY) / CSpeed
        }
        else
        {
            this.Color := "Red"
            this.Logic := ""
        }
    }
    
    LevelAdd()
    {
        Level.Platforms.Insert(this)
        this.Indices.Platforms := Level.Platforms.MaxIndex()
        base.LevelAdd()
    }
}

class _Entity extends _Block
{
    LevelAdd()
    {
        Level.Entities.Insert(this)
        this.Indices.Entities := Level.Entities.MaxIndex()
        base.LevelAdd()
    }
    
    Physics(delta)
    {
        this.NewSpeed.Y := this.Speed.Y
        this.NewSpeed.X := this.Speed.X
        
        if InStr(this.id, "player")
            this.EnemyX := 0, this.EnemyY := 0
        this.Intersect.X := 0
        this.Intersect.Y := 0
        
        for i, rect in Level.Blocks
        {
            if (this == rect)
                continue
            
            X := this.IntersectsX(rect)
            Y := this.IntersectsY(rect)
            
            if (X == "" || Y == "")
                continue
            
            if (Abs(X) > Abs(Y))
            {   ; collision along horizontal
                this.Y += Y ;move out of intersection
                this.Intersect.Y := Y
                this.Friction(Delta, rect, "X")
                
                if (this.Y > rect.Y && this.WantJump && rect.independent) ; ceiling stick, no net effect if it's a movable rect
                    this.NewSpeed.Y -= Gravity * Delta
                else
                {
                    if (this.Y < rect.Y && this.WantJump) ; jump: increase speed *down* and let .Impact() handle the effects on other rects
                        this.NewSpeed.Y += this.JumpSpeed
                    this.Impact(Delta, rect, "Y", Y)
                }
                if InStr(this.id, "player") && InStr(rect.id, "enemy") && !IsObject(this.EnemyY)
                    this.EnemyY := rect
            }
            else
            {   ; collision along vertical
                this.X += X
                this.Intersect.X := X
                this.Friction(Delta, rect, "Y")
                this.Impact(Delta, rect, "X", X)
                
                if (Sign(X) == -this.MoveX && this.MoveX) ; wall climb
                {
                    this.NewSpeed.Y -= Gravity * Delta + (this.WantJump ? this.MoveSpeed * Delta : 0)
                    if rect.independent
                        this.NewSpeed.X *= 0.1
                    else
                        rect.Speed.Y += (Gravity * Delta + this.MoveSpeed * Delta * this.WantJump) * this.mass / rect.mass
                }
                if InStr(this.id, "player") && InStr(rect.id, "enemy")
                    this.EnemyX := True
            }
        }
    }
    
    Impact(delta, rect, dir, int )
    {
        if (Sign(this.NewSpeed[dir]) == Sign(-int)) && Abs(this.NewSpeed[dir]) < 60
            this.NewSpeed[dir] := 0
        else if rect.independent
            this.NewSpeed[dir] := (this.NewSpeed[dir] - rect.Speed[dir]) * -Restitution + rect.Speed[dir]
        else
            this.NewSpeed[dir] := (this.mass*this.NewSpeed[dir] + rect.mass*(rect.Speed[dir] + Restitution*(rect.Speed[dir] - this.NewSpeed[dir])))/(this.mass + rect.mass)
            ; formula slightly modified from: http://en.wikipedia.org/wiki/Coefficient_of_restitution#Speeds_after_impact
    }
    
    Friction(delta, rect, dir)
    {   ; not sure this is 100% right. 
        ; dir: direction of motion
        ; normal: direction normal to motion
        this.NewSpeed[dir] := (this.NewSpeed[dir] - rect.Speed[dir]) * Friction ** delta + rect.Speed[dir]
    }
    
    OutOfBounds()
    {
        If (this.X < -this.Padding || this.X > (Level.Width + this.Padding) || this.Y > (Level.Height + this.Padding)) ;out of bounds
            Return, 1
    }
}

class _Player extends _Entity
{
    __new(id, X, Y, W, H, SpeedX = 0, SpeedY = 0)
    {
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        
        this.mass := W * H * 1.5
        this.independent := false
        this.padding := 100
        
        this.id := id
        this.Indices := {}
        this.LevelAdd()
        
        this.JumpSpeed := 300
        this.MoveSpeed := 800
        this.MoveX := 0
        
        this.EnemyX := this.EnemyY := 0
        this.Intersect := { X: 0, Y: 0 }
        
        this.NewSpeed := { X: SpeedX, Y: SpeedY }
        this.Speed := { X: SpeedX, Y: SpeedY }
    }
    
    LevelAdd()
    {
        ; Level.Players.Insert(this)
        ; this.Indices.Players := Level.Players.MaxIndex()
        base.LevelAdd()
    }
    
    Logic(Delta)
    {
        If this.OutOfBounds()
            Return 1
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
        
        this.MoveX := Left > Right ? -1 : Right > Left ? 1 : 0
        
        this.H := Duck ? 30 : 40
        
        ; health/enemy killing
        If (this.EnemyX || IsObject(this.EnemyY) && this.Y > this.EnemyY.Y)
            Health -= 200 * Delta
        Else If IsObject(this.EnemyY)
        {
            this.EnemyY.LevelRemove()
            Health += 50
        }
        Return, 0
    }
}

class _Enemy extends _Entity
{
    __new(id,  X, Y, W, H, SpeedX = 0, SpeedY = 0)
    {
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        
        this.mass := W * H ; * density
        this.independent := false
        
        this.id := id
        this.Indices := {}
        this.LevelAdd()
        
        this.JumpSpeed := 270
        this.MoveSpeed := 600
        this.MoveX := 0
        this.SeekDistance := 120
        this.padding := 300
        
        this.Seeking := false
        
        this.Intersect := { X: 0, Y: 0 }
        
        this.NewSpeed := {}
        this.Speed := { X: SpeedX, Y: SpeedY }
    }
    
    LevelAdd()
    {
        Level.Enemies.Insert(this)
        this.Indices.Enemies := Level.Enemies.MaxIndex()
        base.LevelAdd()
    }
    
    Logic(Delta)
    {
        if this.OutOfBounds()
            this.LevelRemove()
        else if this.Seeking || Level.Player.Distance(this) < this.SeekDistance 
        {
            this.Seeking := True
            this.WantJump := this.Y >= Level.Player.Y
            this.MoveX := Sign(Level.Player.center().X - this.center().X)
        }
    }
}

Logic_MovingPlatform(this, Delta)
{
    If (this.X > max(this.End.X, this.Start.X) || this.X < min(this.end.Y, this.Start.X)) || (this.Y > max(this.End.Y, this.Start.Y) || this.Y < min(this.end.Y, this.Start.Y))
        this.Cycle *= -1, this.Speed.X *= -1, this.Speed.Y *= -1
    this.X += Delta * (this.Start.X - this.End.X) / this.Cycle
    this.Y += Delta * (this.Start.Y - this.End.Y) / this.Cycle
}

Split(text, char, ignore)
{
    StringSplit, Entry, text, %char%, %ignore%
    ret := []
    loop % Entry0
        ret[A_Index] := Entry%A_Index%
    return ret
}

Sign(x)
{
    return x == 0 ? 0 : x < 0 ? -1 : 1
}

IntersectN(a1, a2, b1, b2)
{
    ; 1's are points, 2's are distances. to change both to points, take out the "\+[ab]1" parts from the min() expression
    ; returns a nonzero integer if they intersect, 0 if they just touch, and "" if they do not intersect
    ; positive if a > b
    sub := b1 > a1 ? b1 : a1 ; max
    a := a2 + a1 - sub
    b := b2 + b1 - sub
    r := b < a ? b : a ; min
    return r >= 0 ? r * (a1 + a2/2 < b1 + b2/2 ? -1 : 1) : ""
}

min(x*)
{
    ; accepts either an array or args
    if (ObjMaxIndex(x) == 1 && IsObject(x[1]))
        x := x[1]
    r := x[1]
    loop % ObjMaxIndex(x)-1
        if (x[A_Index+1] < r)
            r := x[A_Index+1]
    return r
}

max(x*)
{
    ; accepts either an array or args
    if (ObjMaxIndex(x) == 1 && IsObject(x[1]))
        x := x[1]
    r := x[1]
    loop % ObjMaxIndex(x)-1
        if (x[A_Index+1] > r)
            r := x[A_Index+1]
    return r
}

mean(arr)
{
    ret := 0
    loop % arr.MaxIndex()
        ret += arr[A_Index]
    return ret / arr.MaxIndex()
}
