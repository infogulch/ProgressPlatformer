#Include ProgressEngine.ahk

Initialize()
{
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
    
    ;create everything
    For Index, Rectangle In Level.Rectangles
        PlaceRectangle(Rectangle.X, Rectangle.Y, Rectangle.W, Rectangle.H, Rectangle.id, Rectangle.options (Rectangle.Color ? " +Background" Rectangle.Color : ""))
    
    AllowRedraw(GameGui.hwnd)
    WinSet, Redraw, , % "ahk_id" GameGui.hwnd
    
    Gui, Show, % "W" Level.Width " H" Level.Height, ProgressPlatformer
    
    GameGui.Width := Width
    GameGui.Height := Height
}


Step(Delta)
{
    If !WinActive("ahk_id" GameGui.hwnd)
        return 0
    If GetKeyState("Tab","P") ;slow motion
        Delta *= 0.3
    If Input()
        Return, 1
    If Logic(Delta)
        Return, 3
    If Physics(Delta)
        Return, 2
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
    ; O(2E + EB) E: entities, B: blocks
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
    ;update everything
    For Index, Rectangle In Level.Rectangles
    {
        if Rectangle.HasKey("Health")
            GuiControl,, % Rectangle.id, % Rectangle.Health
        GuiControl, Move, % Rectangle.id, % "x" . Rectangle.X . " y" . Rectangle.Y . " w" . Rectangle.W . " h" . Rectangle.H
    }
    Return, 0
}


Logic_MovingPlatform(this, Delta)
{
    if !this.Speed.X && !this.Speed.Y
        this.Speed.X := (this.X - this.End.X) / this.Cycle
        this.Speed.Y := (this.Y - this.End.Y) / this.Cycle
    If (this.X > max(this.End.X, this.Start.X) || this.X < min(this.end.Y, this.Start.X) || this.Y > max(this.End.Y, this.Start.Y) || this.Y < min(this.end.Y, this.Start.Y))
    {
        this.Cycle *= -1, this.Speed.X *= -1, this.Speed.Y *= -1
        
        if this.X > max(this.End.X, this.Start.X)
            this.X := max(this.End.X, this.Start.X)
        else if this.X < min(this.end.Y, this.Start.X)
            this.X := min(this.end.Y, this.Start.X)
        
        if this.Y > max(this.End.Y, this.Start.Y)
            this.Y := max(this.End.Y, this.Start.Y)
        else if this.Y < min(this.end.Y, this.Start.Y)
            this.Y := min(this.end.Y, this.Start.Y)
    }
    this.X += Delta * (this.Start.X - this.End.X) / this.Cycle
    this.Y += Delta * (this.Start.Y - this.End.Y) / this.Cycle
}
