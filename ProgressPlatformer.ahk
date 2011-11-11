#NoEnv
#SingleInstance, Force

    global TargetFrameRate := 100
    global TargetFrameMs := 1000 / TargetFrameRate
    
    global Gravity := 981
    global Friction := 0.01
    global Restitution := 0.6
    
    global Level, LevelIndex := 1
    global Left, Right, Jump, Duck, Health
    
    global GameGui
    DeltaLimit := 0.05
    
    SetBatchLines, -1
    SetWinDelay, -1
    
    GoSub MakeGuis
    GoSub GameInit
return

#IF WinActive("ahk_id" GameGui.hwnd)
F5::
GameInit:
    If Initialize()
    {
        MsgBox, Game complete!
        ExitApp
    }
    PreviousTime := A_TickCount
    SetTimer StepThrough, % TargetFrameMs
return

StepThrough:
    Delta := (A_TickCount - PreviousTime) / 1000
    If (Delta > DeltaLimit)
        Delta := DeltaLimit
    PreviousTime := A_TickCount
    if Step(Delta)
    {
        SetTimer, %A_ThisLabel%, Off
        SetTimer GameInit, -1
    }
return

MakeGuis:
    ;create game window
    Gui, Color, Black
    Gui, +OwnDialogs +LastFound
    
    GameGui := []
    GameGui.hwnd := WinExist()
    
    GameGui.count := []
    GameGui.count.BlockRectangle  := 0
    GameGui.count.PlayerRectangle := 0
    GameGui.count.GoalRectangle   := 0
    GameGui.count.EnemyRectangle  := 0
return

GuiEscape:
GuiClose:
ExitApp

Initialize() {
    Health := 100

    LevelFile := A_ScriptDir . "\Levels\Level " . LevelIndex . ".txt"
    If !FileExist(LevelFile)
        Return, 1
    FileRead, LevelDefinition, %LevelFile%
    If ErrorLevel
        Return, 1
    Level := ParseLevel(LevelDefinition)
    
    HideProgresses()
    
    ;create level
    For Index, rect In Level.Blocks
        PutProgress(rect.X, rect.Y, rect.W, rect.H, "BlockRectangle", A_Index, "BackgroundRed")
    
    ;create player
    PutProgress(Level.Player.X, Level.Player.Y, Level.Player.W, Level.Player.H, "PlayerRectangle", "", "-Smooth Vertical")
    
    ;create goal
    PutProgress(Level.Goal.X, Level.Goal.Y, Level.Goal.W, Level.Goal.H, "GoalRectangle", "", "Disabled -VScroll")
    
    ;create enemies
    For Index, rect In Level.Enemies
        PutProgress(rect.X, rect.Y, rect.W, rect.H, "EnemyRectangle", A_Index, "BackgroundBlue")

    Gui, Show, AutoSize, ProgressPlatformer
    
    WinGetPos,,, Width, Height, % "ahk_id" GameGui.hwnd
    GameGui.Width := Width
    GameGui.Height := Height
}

PutProgress(x, y, w, h, name, i, options) {
    global
    local hwnd
    pos := "x" x " y" y " w" w " h" h
    if (i > GameGui.count[name] || GameGui.count[name] == 0)
    {
        GameGui.count[name]++
        Gui, Add, Progress, v%name%%i% %pos% %options% hwndhwnd, 0
        Control, ExStyle, -0x20000, , ahk_id%hwnd% ; WS_EX_STATICEDGE
    }
    else {
        GuiControl, Show, %name%%i%
        GuiControl, Move, %name%%i%, %pos%
    }
}

HideProgresses() {
    global
    for name, count in GameGui.count
        loop % count
            GuiControl, Hide, %name%%A_Index%
}

Step(Delta) {
    If !WinActive("ahk_id" GameGui.hwnd)
        return 0
    If GetKeyState("Tab","P") ;slow motion
        Delta /= 2
    If x := Input()
        Return, 1 ", " x
    If x := Physics(Delta)
        Return, 2 ", " x
    If x := Logic(Delta)
        Return, 3 ", " x
    If x := EnemyLogic(Delta)
        Return, 4 ", " x
    If x := Update()
        Return, 5 ", " x
    Return, 0
}

Input() {
    Left  := GetKeyState("Left","P")  || GetKeyState("A", "P")
    Duck  := GetKeyState("Down","P")  || GetKeyState("S", "P")
    Jump  := GetKeyState("Up","P")    || GetKeyState("W", "P")
    Right := GetKeyState("Right","P") || GetKeyState("D", "P")
    Return, 0
}

Physics( delta ) {
    ; O(N + N*(N + K)) N: entities, K: blocks
    local entity
    
    ; apply physics, only changes NewSpeed
    for i, entity in Level.Entities
        entity.physics(delta)
    
    ; apply changes in speeds to position
    for i, entity in Level.Entities
    {
        entity.X += delta * entity.Speed.X := entity.NewSpeed.X
        entity.Y += delta * entity.Speed.Y := entity.NewSpeed.Y
        
        ; msgbox % entity.type "`nvelocities: " entity.speed.x ", " entity.speed.y " (" entity.NewSpeed.X ", " entity.NewSpeed.Y ")`npositions: " entity.X ", " entity.Y
    }
}

Logic(Delta) {
    MoveSpeed := 800
    JumpSpeed := 200
    JumpInterval := 250
    
    Padding := 100
    If (Level.Player.X < -Padding || Level.Player.X > (GameGui.Width + Padding) || Level.Player.Y > (GameGui.Height + Padding)) ;out of bounds
        Return, 1
    If (Health <= 0) ;out of health
        Return, 2
    If Level.Player.Inside(Level.Goal) ;reached goal
    {
        Score := Round(Health)
        MsgBox, You win!`n`nYour score was %Score%.
        LevelIndex++ ;move to the next level
        Return, 3
    }
    
    ; TODO: prioritize the most recently pressed key
    If Left
        Level.Player.NewSpeed.X -= MoveSpeed * Delta
    If Right
        Level.Player.NewSpeed.X += MoveSpeed * Delta
    
    ; wall climb
    If (Level.Player.Intersect.X && (Left || Right))
    {
        Level.Player.NewSpeed.Y -= Gravity * Delta
        If Jump
            Level.Player.NewSpeed.Y += MoveSpeed * Delta
    }
    
    Level.Player.WantJump := Jump
    
    Level.Player.H := Duck ? 30 : 40
    
    ; health/enemy killing
    If (Level.Player.EnemyX || Level.Player.EnemyY > 0)
        Health -= 200 * Delta
    Else If Level.Player.EnemyY
    {
        enemy := Level.Rectangles.Remove(Abs(Level.Player.EnemyY),"")
        Level.Enemies.Remove(enemy.indices.enemies,"")
        Level.Entities.Remove(enemy.indices.entities,"")
        GuiControl, Hide, % "EnemyRectangle" enemy.indices.enemies
        Health += 50
    }
    Return, 0
}

EnemyLogic(Delta) {
    MoveSpeed := 600, JumpSpeed := 150, SeekDistance := 200
    for i, rect In Level.Enemies
        if Level.Player.Distance(rect) < SeekDistance
        {
            rect.WantJump := rect.Y <= Level.Player.Y
            if rect.WantJump && rect.IntersectsX(Level.Player) ;directly underneath the player
                rect.NewSpeed.X += MoveSpeed * Delta * -Sign(Level.Player.X - rect.X)
            else
                rect.NewSpeed.X += MoveSpeed * Delta * Sign(Level.Player.X - rect.X)
        }
}

Update() {
    ;update level
    For Index, Rectangle In Level.Blocks
        GuiControl, Move, LevelRectangle%Index%, % "x" . Rectangle.X . " y" . Rectangle.Y . " w" . Rectangle.W . " h" . Rectangle.H

    ;update player
    GuiControl,, PlayerRectangle, %Health%
    GuiControl, Move, PlayerRectangle, % "x" . Level.Player.X . " y" . Level.Player.Y . " w" . Level.Player.W . " h" . Level.Player.H

    ;update enemies
    For Index, Rectangle In Level.Enemies
        GuiControl, Move, EnemyRectangle%Index%, % "x" . Rectangle.X . " y" . Rectangle.Y . " w" . Rectangle.W . " h" . Rectangle.H
    Return, 0
}

ParseLevel(LevelDefinition) {
    ; Object/Level Heirarchy:
    ; 
    ; Rectangles: Everything collide-able
    ;   Blocks: fixed rectangle
    ;   Entities: movable rectangle
    ;       Player: player-controlled entity
    ;       Enemies: AI-controlled entity
    ; 
    local Level := Object()

    Level.Rectangles := []
    Level.Blocks     := []
    Level.Entities   := []
    Level.Enemies    := []
    
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
            rect.Type :=  "Block" A_Index
            rect.Indices := {}
            rect.Indices.Blocks     := Level.Blocks.Insert(rect)
            rect.Indices.Rectangles := Level.Rectangles.Insert(rect)
        }
    }
    
    If RegExMatch(LevelDefinition,"iS)Player\s*:\s*\K(?:\d+\s*(?:,\s*\d+\s*){3,5})*",Property)
    {
        Entry5 := 0, Entry6 := 0
        StringSplit, Entry, Property, `,, %A_Space%`t`r`n
        
        player := new _Entity(Entry1,Entry2,Entry3,Entry4,Entry5,Entry6)
        player.Type := "Player"
        player.Indices := {}
        Level.Player := player
        player.Indices.Rectangles := Level.Rectangles.insert(player)
        player.Indices.Entities   := Level.Entities.insert(player)
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
            
            enemy := new _Entity(Entry1,Entry2,Entry3,Entry4,Entry5,Entry6)
            enemy.Type := "Enemy" A_Index
            enemy.Indices := {}
            enemy.Indices.Enemies    := Level.Enemies.insert(enemy)
            enemy.Indices.Rectangles := Level.Rectangles.insert(enemy)
            enemy.Indices.Entities   := Level.Entities.insert(enemy)
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
    return, Level
}

class _Rectangle {
    __new(X,Y,W,H){
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        this.fixed := true
        this.Speed := { X: 0, Y: 0 }
    }
    
    Center() {
        return { X: this.X + this.W / 2, Y: this.Y + this.H / 2 }
    }
    
    ; Distance between the *centers* of two rects
    CenterDistance( rect ) {
        a := this.Center()
        b := rect.Center()
        return Sqrt( Abs(a.X - b.X)**2 + Abs(a.Y - b.Y)**2 )
    }
    
    ; calculates the closest distace between two rects (*not* the centers)
    Distance( rect ) {
        X := this.IntersectsX(rect) ? 0 : min(Abs(this.X - (rect.X+rect.W)), Abs(rect.X - (this.X+this.W)))
        Y := this.IntersectsY(rect) ? 0 : min(Abs(this.Y - (rect.Y+rect.H)), Abs(rect.Y - (this.Y+this.H)))
        return Sqrt(X**2 + Y**2)
    }
    
    ; returns true if this is completely inside rect
    Inside( rect ) {
        return (this.X >= rect.X) && (this.Y >= rect.Y) && (this.X + this.W <= rect.X + rect.W) && (this.Y + this.H <= rect.Y + rect.H)
    }
    
    Intersects( rect ) {
        ; returns a value that can be treated as boolean true if `this` intersects `rect`
        ; 1 if it intersects and the x-intersection is greater than the y-intersection.
        ; -1 if it intersects and the y-intersection is greater than the x-intersection.
        ; 1 if they intersect equally
        ; 0 if they do not intersect at all.
        x := this.IntersectsX(rect) 
        return this.IntersectsY(rect) > x ? -1 : !!x
    }
    
    ; returns the amount of intersection or 0
    IntersectX( rect ) {
        return IntersectN(this.X, this.W, rect.X, rect.W)
    }
    
    IntersectY( rect ) {
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
        
        this.JumpSpeed := 150
        
        ; !!! All changes to speed are done on NewSpeed, and copied after all calculations are finished
        this.NewSpeed := { X: SpeedX, Y: SpeedY }
        this.Speed := { X: SpeedX, Y: SpeedY }
    }
    
    Physics( delta ) {
        this.NewSpeed.Y += Gravity * delta
        
        for i, rect in Level.Rectangles
        {
            if (this == rect)
                continue
            
            X := this.IntersectX(rect)
            Y := this.IntersectY(rect)
            
            if (X == "" || Y == "") ;|| (X == 0 && Y == 0)
            {
                this.Intersect.X := 0
                this.Intersect.Y := 0
                continue
            }
            this.Intersect.X := X
            this.Intersect.Y := Y
            
            if this.type = "player" && InStr(rect.type, "enemy")
                this.EnemyX := True, this.EnemyY := i * Sign(Y)
            else
                this.EnemyX := False, this.EnemyY := 0
            
            if (Abs(X) > Abs(Y))
            {
                this.Y += Y
                this.Impact(rect, "Y")
                this.Friction(delta, rect, "X")
                
                if (this.WantJump && Rect.Y = Round(this.Y + this.H))
                {
                    this.NewSpeed.Y -= this.JumpSpeed + Gravity * delta
                    if !rect.fixed
                        rect.NewSpeed.Y += this.JumpSpeed + Gravity * delta
                }
            }
            else
            {
                this.X += X
                this.Impact(rect, "X")
                this.Friction(delta, rect, "Y")
            }
        }
    }
    
    Impact( rect, dir ) {
        if rect.fixed
            this.NewSpeed[dir] := this.Speed[dir] * -Restitution ; / 2 if button is pressed in same direction of Speed[dir]
        else
            this.NewSpeed[dir] := (this.mass*this.Speed[dir] + rect.mass*(rect.Speed[dir] + Restitution*(rect.Speed[dir] - this.Speed[dir])))/(this.mass + rect.mass)
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

Sign( x ) {
    return x == 0 ? 0 : x < 0 ? -1 : 1
}

IntersectN(a1, a2, b1, b2) {
    ; 1's are points, 2's are distances. to change both to points, take out the "\+[ab]1" parts from the min() expression
    ; returns a positive number if they intersect, 0 if they just touch, and "" if they do not intersect
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
