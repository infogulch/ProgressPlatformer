#NoEnv
#SingleInstance, Force

    global TargetFrameRate := 40
    global TargetFrameMs := 1000 / TargetFrameRate
    
    global Gravity := -981
    global Friction := 0.01
    global Restitution := .6

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
    Temp1 := (A_TickCount - PreviousTime) / 1000
    PreviousTime := A_TickCount
    stepret := Step(Temp1)
    if (stepret == -1)
        PreviousTime := A_TickCount
    else if (stepret) 
    {
        SetTimer, %A_ThisLabel%, Off
        SetTimer GameInit, -0
    }
return

global GameGui

global Level, LevelIndex := 1, Left, Right, Jump, Duck

MakeGuis:
    ;create game window
    Gui, Color, Black
    Gui, +OwnDialogs +LastFound
    
    GameGui := []
    GameGui.hwnd := WinExist()
    
    GameGui.count := []
    GameGui.count.LevelRectangle  := 0
    GameGui.count.PlayerRectangle := 0
    GameGui.count.GoalRectangle   := 0
    GameGui.count.EnemyRectangle  := 0
return

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
    Level := ParseLevel(LevelDefinition)
    
    HideProgresses()
    
    ;create level
    For Index, rect In Level.Blocks
        PutProgress(rect.X, rect.Y, rect.W, rect.H, "LevelRectangle", Index, "BackgroundRed")

    ;create player
    PutProgress(Level.Player.X, Level.Player.Y, Level.Player.W, Level.Player.H, "PlayerRectangle", "", "-Smooth Vertical")

    ;create goal
    PutProgress(Level.Goal.X, Level.Goal.Y, Level.Goal.W, Level.Goal.H, "GoalRectangle", "", "Disabled -VScroll")

    ;create enemies
    For Index, rect In Level.Enemies
        PutProgress(rect.X, rect.Y, rect.W, rect.H, "EnemyRectangle", Index, "BackgroundBlue")

    Gui, Show, AutoSize, ProgressPlatformer
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

Step(Delta)
{
    Gui, +LastFound
    If !WinActive() || GetKeyState("LButton", "P") || GetKeyState("RButton", "P") ;pause game if window is not active or mouse is held down
        Return, -1
    If GetKeyState("Tab","P") ;slow motion
        Delta /= 2
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
    Left  := GetKeyState("Left","P")  || GetKeyState("A", "P")
    Duck  := GetKeyState("Down","P")  || GetKeyState("S", "P")
    Jump  := GetKeyState("Up","P")    || GetKeyState("W", "P")
    Right := GetKeyState("Right","P") || GetKeyState("D", "P")
    Return, 0
}

Logic(Delta)
{
    global EnemyX, EnemyY
    MoveSpeed := 800
    JumpSpeed := 200
    JumpInterval := 250

    Padding := 100
    WinGetPos,,, Width, Height, % "ahk_id" GameGui.hwnd
    If (Level.Player.X < -Padding || Level.Player.X > (Width + Padding) || Level.Player.Y > (Height + Padding)) ;out of bounds
        Return, 1
    If (Health <= 0) ;out of health
        Return, 2
    If Inside(Level.Player,Level.Goal) ;reached goal
    {
        Score := Round(Health)
        MsgBox, You win!`n`nYour score was %Score%.
        LevelIndex++ ;move to the next level
        Return, 3
    }

    If Left
        Level.Player.SpeedX -= MoveSpeed * Delta
    If Right
        Level.Player.SpeedX += MoveSpeed * Delta

    If (Level.Player.IntersectX && (Left || Right))
    {
        Level.Player.SpeedY -= Gravity * Delta
        If Jump
                Level.Player.SpeedY += MoveSpeed * Delta
    }
    Else If (Jump && Level.Player.LastContact < JumpInterval)
        Level.Player.SpeedY += JumpSpeed - (Gravity * Delta), Level.Player.LastContact := JumpInterval
    Level.Player.LastContact += Delta

    Level.Player.H := Duck ? 30 : 40

    If (EnemyX || EnemyY > 0)
        Health -= 200 * Delta
    Else If EnemyY
    {
        EnemyY := Abs(EnemyY)
        ObjRemove(Level.Enemies,EnemyY,"")
        GuiControl, Hide, EnemyRectangle%EnemyY%
        Health += 50
    }

    EnemyLogic(Delta)
    Return, 0
}

EnemyLogic(Delta)
{
    MoveSpeed := 600, JumpSpeed := 150, JumpInterval := 200
    For Index, Rectangle In Level.Enemies
    {
        If ((Level.Player.Y - Rectangle.Y) < JumpSpeed && Abs(Level.Player.X - Rectangle.X) < (MoveSpeed / 2))
        {
            If (Rectangle.Y >= Level.Player.Y)
            {
                If Rectangle.IntersectX
                    Rectangle.SpeedY += (MoveSpeed - Gravity) * Delta
                Else If (Rectangle.LastContact < JumpInterval)
                    Rectangle.SpeedY += JumpSpeed - (Gravity * Delta), Rectangle.LastContact := JumpInterval
            }
            If (Rectangle.X > Level.Player.X)
                Rectangle.SpeedX -= MoveSpeed * Delta
            Else
                Rectangle.SpeedX += MoveSpeed * Delta
        }
        Rectangle.LastContact += Delta
    }
}

Physics(Delta)
{
    global EnemyX, EnemyY
    ;process player
    Level.Player.SpeedY += Gravity * Delta ;process gravity
    Level.Player.X += Level.Player.SpeedX * Delta
    Level.Player.Y -= Level.Player.SpeedY * Delta ;process momentum
    EntityPhysics(Delta,Level.Player,Level.Blocks) ;process collision with level

    EnemyX := 0, EnemyY := 0
    For Index, Rectangle In Level.Enemies
    {
        ;process enemy
        Rectangle.SpeedY += Gravity * Delta ;process gravity
        Rectangle.X += Rectangle.SpeedX * Delta, Rectangle.Y -= Rectangle.SpeedY * Delta ;process momentum
        EntityPhysics(Delta,Rectangle,Level.Blocks) ;process collision with level
        Temp1 := ObjClone(Level.Enemies), ObjRemove(Temp1,Index,"") ;create an array of enemies excluding the current one
        EntityPhysics(Delta,Rectangle,Temp1) ;process collision with other enemies

        If !Collide(Rectangle,Level.Player,IntersectX,IntersectY) ;player did not collide with the rectangle
            Continue
        If (Abs(IntersectX) > Abs(IntersectY)) ;collision along top or bottom side
        {
            EnemyY := (IntersectY < 0) ? -Index : Index
            Rectangle.Y -= IntersectY ;move the player out of the intersection area
            Level.Player.Y += IntersectY ;move the player out of the intersection area

            Temp1 := ((Rectangle.SpeedX + Level.Player.SpeedX) / 2) * Restitution
            Rectangle.SpeedY := Temp1 ;reflect the speed and apply damping
            Level.Player.SpeedY := -Temp1 ;reflect the speed and apply damping
        }
        Else ;collision along left or right side
        {
            EnemyX := Index
            Rectangle.X -= IntersectX ;move the player out of the intersection area
            Level.Player.X += IntersectX ;move the player out of the intersection area

            Temp1 := ((Rectangle.SpeedX + Level.Player.SpeedX) / 2) * Restitution
            Rectangle.SpeedX := Temp1 ;reflect the speed and apply damping
            Level.Player.SpeedX := -Temp1 ;reflect the speed and apply damping
        }
        If EnemyY
        Rectangle.SpeedX *= (Friction * Abs(IntersectX)) ** Delta ;apply friction
        If EnemyX
            Rectangle.SpeedY *= (Friction * Abs(IntersectY)) ** Delta ;apply friction
    }
    Return, 0
}

EntityPhysics(Delta,Entity,Rectangles)
{
    CollisionX := 0, CollisionY := 0, TotalIntersectX := 0, TotalIntersectY := 0
    For Index, Rectangle In Rectangles
    {
        If !Collide(Entity,Rectangle,IntersectX,IntersectY) ;entity did not collide with the rectangle
            Continue
        If (Abs(IntersectX) >= Abs(IntersectY)) ;collision along top or bottom side
        {
            CollisionY := 1
            Entity.Y -= IntersectY ;move the entity out of the intersection area
            Entity.SpeedY *= -Restitution ;reflect the speed and apply damping
            TotalIntersectY += Abs(IntersectY)
        }
        Else ;collision along left or right side
        {
            CollisionX := 1
            Entity.X -= IntersectX ;move the entity out of the intersection area
            Entity.SpeedX *= -Restitution ;reflect the speed and apply damping
            TotalIntersectX += Abs(IntersectX)
        }
    }
    Entity.IntersectX := TotalIntersectX, Entity.IntersectY := TotalIntersectY
    If CollisionY
    {
        Entity.LastContact := 0
        Entity.SpeedX *= (Friction * TotalIntersectY) ** Delta ;apply friction
    }
    If CollisionX
    {
        Entity.IntersectY := TotalIntersectY
        Entity.SpeedY *= (Friction * TotalIntersectX) ** Delta ;apply friction
    }
}

Update()
{
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

; Object/Level Heirarchy:
; 
; Rectangles: Everything collide-able
;   Blocks: fixed rectangle
;   Entities: movable rectangle
;       Player: player-controlled entity
;       Enemies: AI-controlled entity
; 

ParseLevel(LevelDefinition)
{
    local Level := Object()

    Level.Rectangles := []
    Level.Blocks := []
    Level.Entities := []
    Level.Enemies := []
    
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
            Level.Blocks.Insert(rect)
            Level.Rectangles.Insert(rect)
        }
    }
    If RegExMatch(LevelDefinition,"iS)Player\s*:\s*\K(?:\d+\s*(?:,\s*\d+\s*){3,5})*",Property)
    {
        Entry5 := 0, Entry6 := 0
        StringSplit, Entry, Property, `,, %A_Space%`t`r`n
        
        player := new _Entity(Entry1,Entry2,Entry3,Entry4,Entry5,Entry6)
        Level.Player := player
        Level.Rectangles.insert(player)
        Level.Entities.insert(player)
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
            Level.Enemies.insert(enemy)
            Level.Rectangles.insert(enemy)
            Level.Entities.insert(enemy)
        }
    }
    return, Level
}

class _Rectangle {
    __new(X,Y,W,H){
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        this.fixed := true
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
    
    ; returns a value that can be treated as boolean true if `this` intersects `rect`
    ; 1 if it intersects and the x-intersection is greater than the y-intersection.
    ; -1 if it intersects and the y-intersection is greater than the x-intersection.
    ; 1 if they intersect equally
    ; 0 if they do not intersect at all.
    Intersects( rect ) {
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
    
    IntersectN( n1, d1, n2, d2 ) {
        r := -Abs(n1-n2) + min(d1, d2)
        return r > 0 ? r : 0
    }
}

class _Entity extends _Rectangle {
    __new(X,Y,W,H,SpeedX = 0,SpeedY = 0) {
        this.X := X
        this.Y := Y
        this.W := W
        this.H := H
        this.mass := W * H ; * density
        this.fixed := false
        this.SpeedX := SpeedX
        this.SpeedY := SpeedY
        this.AccelX := 0 ; arrow direction
        this.AccelY := 0
    }
    
    Physics( delta ) {
        ; get a rough radius to check for collisions
        ; dist := 2*Sqrt((this.SpeedX + this.AccelX/TargetFrameRate)**2 + (this.SpeedY + this.AccelY/TargetFrameRate))
        
        for i, rect in Level.Rectangles
        {
            x := this.IntersectX(rect)
            y := this.IntersectY(rect)
            if !(x && y)
                continue
            
            
        }
    }
}

Between( x, a, b ) {
    return (a >= x && x >= b)
}

; min that accepts either an array or args
min( x* ) {
    if (ObjMaxIndex(x) == 1 && IsObject(x[1]))
        x := x[1]
    r := x[1]
    loop % ObjMaxIndex(x)-1
        if (x[1] < r)
            r := x[1]
    return r
}

Collide(Rectangle1,Rectangle2,ByRef IntersectX = "",ByRef IntersectY = "")
{
    Left1 := Rectangle1.X, Left2 := Rectangle2.X, Right1 := Left1 + Rectangle1.W, Right2 := Left2 + Rectangle2.W
    Top1 := Rectangle1.Y, Top2 := Rectangle2.Y, Bottom1 := Top1 + Rectangle1.H, Bottom2 := Top2 + Rectangle2.H

    ;check for collision
    If (Right1 < Left2 || Right2 < Left1 || Bottom1 < Top2 || Bottom2 < Top1)
    {
        IntersectX := 0, IntersectY := 0
        Return, 0 ;no collision occurred
    }

    ;find width of intersection
    If (Left1 < Left2)
        IntersectX := ((Right1 < Right2) ? Right1 : Right2) - Left2
    Else
        IntersectX := Left1 - ((Right1 < Right2) ? Right1 : Right2)

    ;find height of intersection
    If (Top1 < Top2)
        IntersectY := ((Bottom1 < Bottom2) ? Bottom1 : Bottom2) - Top2
    Else
        IntersectY := Top1 - ((Bottom1 < Bottom2) ? Bottom1 : Bottom2)
    Return, 1 ;collision occurred
}

Inside(Rectangle1,Rectangle2)
{
    Return, Rectangle1.X >= Rectangle2.X && (Rectangle1.X + Rectangle1.W) <= (Rectangle2.X + Rectangle2.W) && Rectangle1.Y >= Rectangle2.Y && (Rectangle1.Y + Rectangle1.H) <= (Rectangle2.Y + Rectangle2.H)
}
