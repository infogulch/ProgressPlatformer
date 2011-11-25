#NoEnv
#SingleInstance Force

    TargetFrameRate := 50
    
    global Gravity := 981
    global Friction := .01
    global Restitution := 0.6
    
    global Level, LevelIndex := 1
    global Left, Right, Jump, Duck
    
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

PlaceRectangle(X, Y, W, H, id, Options = "")
{
    global
    static NameCount := Object()
    local hWnd, _, _Name, _Index
    RegExMatch(id, "i)^(?<Name>[a-z]+)(?<Index>\d+)?$", _)
    If !NameCount.Haskey(_Name)
        NameCount[_Name] := 0
    If ((_Index = "" && NameCount[_Name] = 0) || NameCount[_Name] < _Index) ;control does not yet exist
    {
        NameCount[_Name]++
        Gui, Add, Progress, x%X% y%Y% w%W% h%H% v%id% %Options% hwndhwnd, 0
        Control, ExStyle, -0x20000, , ahk_id%hwnd% ;remove WS_EX_STATICEDGE extended style
    }
    Else
    {
        GuiControl, -Background %Options%, %id%
        GuiControlGet, hwnd, hwnd, %id%
        Control, ExStyle, -0x20000, , ahk_id%hwnd%
        GuiControl, Show, %id%
        GuiControl, Move, %id%, x%X% y%Y% w%W% h%H%
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
    
    If RegExMatch(LevelDefinition,"iS)Goal\s*:\s*\K(?:\d+\s*(?:,\s*\d+\s*){3})*",Property)
        Level.Goal := new _Area("GoalRectangle", Split(Property, ",", " `t`r`n")*)
    If RegExMatch(LevelDefinition,"iS)Enemies\s*:\s*\K(?:\d+\s*(?:,\s*\d+\s*){3,5})*",Property)
    {
        Property := RegExReplace(Property, "(\r?\n){2,}", "$1")
        Loop, Parse, Property, `n, `r `t
            (new _Enemy("EnemyRectangle" A_Index, Split(A_LoopField, ",", " `t`r`n")*))
    }
    If RegExMatch(LevelDefinition,"iS)Player\s*:\s*\K(?:\d+\s*(?:,\s*\d+\s*){3,5})*",Property)
        Level.Player := new _Player("PlayerRectangle", Split(Property, ",", " `t`r`n")*)
    If RegExMatch(LevelDefinition,"iS)\s*Platforms\s*:\s*\K(?:-?\d+\s*(?:,\s*-?\d+\s*){3,7})*",Property)
    {
        Property := RegExReplace(Property, "(\r?\n){2,}", "$1")
        Loop, Parse, Property, `n
            (new _Platform("PlatformRectangle" A_Index, Split(A_LoopField, ",", " `t`r`n")*))
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
    static LevelArray := "Rectangles"
    
    X := 0
    Y := 0
    W := 0
    H := 0
    Options := ""
    
    LevelAdd()
    {
        this.Indices := {}
        b := this
        while IsObject(b := b.base)
        {
            name := b.LevelArray
            Level[name].Insert(this)
            this.Indices[name] := Level[name].MaxIndex()
        }
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
    static LevelArray := "Areas"
    
    Color := "White"
    
    __new(id, X, Y, W, H, LogicCallout = "")
    {
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        this.Logic := LogicCallout
        this.id := id
        this.Speed := { X: 0, Y: 0 }
        
        this.LevelAdd()
    }
}

class _Block extends _Rectangle
{
    static LevelArray := "Blocks"
    
    Speed := { X: 0, Y: 0 }
}

class _Platform extends _Block
{
    static LevelArray := "Platforms"
    
    independent := true
    Color := "Red"
    Logic := ""
    
    __new(id, X, Y, W, H, EndX = "", EndY = "", CSpeed = 0)
    {
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        
        this.id := id
        this.LevelAdd()
        
        if (EndX != "")
        {
            this.Color := "Lime"
            this.Logic := "Logic_MovingPlatform"
            this.Start := { X: X, Y: Y }
            this.End := { X: EndX, Y: EndY }
            this.Cycle := CSpeed
        }
        
        if IsFunc(this.Logic)
        {
            if !IsObject(this.Logic)
                this.Logic := Func(this.Logic)
            this.Logic.(this, 0)
        }
    }
}

class _Entity extends _Block
{
    static LevelArray := "Entities"
    
    NewSpeed := {}
    Intersect := { X: 0, Y: 0 }
    independent := false
    padding := 100
    
    JumpSpeed := 270
    MoveSpeed := 600
    MoveX := 0
    
    Health := 0
    
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
        if (Sign(this.NewSpeed[dir]) == Sign(-int)) && Abs(this.NewSpeed[dir]) < 50
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
        If (this.X < -this.Padding || this.X > (Level.Width + this.Padding) || this.Y > (Level.Height + this.Padding))
            Return, 1
    }
}

class _Player extends _Entity
{
    static LevelArray := "Players"
    
    Health := 100
    Options := "-Smooth Vertical"
    
    __new(id, X, Y, W, H, SpeedX = 0, SpeedY = 0)
    {
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        
        this.mass := W * H * 1.5
        
        this.id := id
        this.LevelAdd()
        
        this.JumpSpeed := 320
        this.MoveSpeed := 800
        this.MoveX := 0
        
        this.EnemyX := 0, this.EnemyY := 0
        
        this.Speed.X := SpeedX
        this.Speed.Y := SpeedY
    }
    
    Logic(Delta)
    {
        If this.OutOfBounds()
            Return 1
        If (this.Health <= 0) ;out of health
            Return, 2
        If this.Inside(Level.Goal) ;reached goal
        {
            Score := Round(this.Health)
            MsgBox, You win!`n`nYour score was %Score%.
            LevelIndex++ ;move to the next level
            Return, 3
        }
        this.WantJump := Jump
        
        this.MoveX := Left > Right ? -1 : Right > Left ? 1 : 0
        
        this.H := Duck ? 30 : 40
        
        ; health/enemy killing
        If (this.EnemyX || IsObject(this.EnemyY) && this.Y > this.EnemyY.Y)
            this.Health -= 200 * Delta
        Else If IsObject(this.EnemyY)
        {
            this.EnemyY.LevelRemove()
            this.Health += 50
        }
        Return, 0
    }
}

class _Enemy extends _Entity
{
    static LevelArray := "Enemies"
    
    Color := "Blue"
    
    __new(id,  X, Y, W, H, SpeedX = 0, SpeedY = 0)
    {
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        
        this.mass := W * H ; * density
        
        this.id := id
        this.LevelAdd()
        
        this.SeekDistance := 120
        this.Seeking := false
        
        this.Speed.X := SpeedX
        this.Speed.Y := SpeedY
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
