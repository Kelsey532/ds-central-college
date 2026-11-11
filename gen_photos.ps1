Add-Type -AssemblyName System.Drawing

# Create images/school/main-hall.jpg (800x600)
$bmpHall = New-Object System.Drawing.Bitmap(800, 600)
$g = [System.Drawing.Graphics]::FromImage($bmpHall)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

# Dusk emerald gradient sky
$skyBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.PointF(0, 0)),
    (New-Object System.Drawing.PointF(0, 400)),
    [System.Drawing.Color]::FromArgb(11, 42, 32),
    [System.Drawing.Color]::FromArgb(26, 85, 65)
)
$g.FillRectangle($skyBrush, 0, 0, 800, 400)

# Ground grass
$grassBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.PointF(0, 400)),
    (New-Object System.Drawing.PointF(0, 600)),
    [System.Drawing.Color]::FromArgb(7, 35, 25),
    [System.Drawing.Color]::FromArgb(3, 15, 10)
)
$g.FillRectangle($grassBrush, 0, 400, 800, 200)

# School Building Facade
$bldgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(215, 222, 218))
$roofBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140, 50, 40))
$winBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(15, 30, 25))
$goldPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(224, 181, 58), 3)

# Main Block
$g.FillRectangle($bldgBrush, 120, 220, 560, 220)
$g.DrawRectangle($goldPen, 120, 220, 560, 220)

# Roof
$pts = @(
    (New-Object System.Drawing.Point(80, 220)),
    (New-Object System.Drawing.Point(400, 130)),
    (New-Object System.Drawing.Point(720, 220))
)
$g.FillPolygon($roofBrush, $pts)

# Windows
for ($x = 160; $x -lt 640; $x += 60) {
    $g.FillRectangle($winBrush, $x, 260, 35, 50)
    $g.FillRectangle($winBrush, $x, 340, 35, 65)
}

# Grand Pillars
$pillarBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(240, 245, 242))
$g.FillRectangle($pillarBrush, 340, 220, 30, 220)
$g.FillRectangle($pillarBrush, 430, 220, 30, 220)

# Text Badge
$badgeFont = New-Object System.Drawing.Font("Georgia", 18, [System.Drawing.FontStyle]::Bold)
$subFont = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Regular)
$goldBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(224, 181, 58))
$whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 255))
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center

$g.DrawString("D.S. SENANAYAKE CENTRAL COLLEGE", $badgeFont, $goldBrush, 400, 480, $sf)
$g.DrawString("Main Administrative Complex & Campus Quadrangle", $subFont, $whiteBrush, 400, 520, $sf)

$bmpHall.Save("$PWD\images\school\main-hall.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose()
$bmpHall.Dispose()

# Create gallery images 1, 2, 3
$cats = @("Sports", "Academics", "Cultural Events", "Science Fair", "Colours Night", "Prize Giving")
for ($i = 1; $i -le 6; $i++) {
    $b = New-Object System.Drawing.Bitmap(600, 450)
    $gb = [System.Drawing.Graphics]::FromImage($b)
    $gb.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    
    $cBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF(0, 0)),
        (New-Object System.Drawing.PointF(600, 450)),
        [System.Drawing.Color]::FromArgb(15, 60, 45),
        [System.Drawing.Color]::FromArgb(4, 20, 15)
    )
    $gb.FillRectangle($cBrush, 0, 0, 600, 450)
    
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(224, 181, 58), 2)
    $gb.DrawRectangle($pen, 15, 15, 570, 420)
    
    $fTitle = New-Object System.Drawing.Font("Georgia", 22, [System.Drawing.FontStyle]::Bold)
    $fSub = New-Object System.Drawing.Font("Arial", 13, [System.Drawing.FontStyle]::Regular)
    $catName = $cats[$i - 1]
    
    $gb.DrawString($catName, $fTitle, $goldBrush, 300, 190, $sf)
    $gb.DrawString("D.S. Senanayake Central College, Mirigama", $fSub, $whiteBrush, 300, 240, $sf)
    
    $b.Save("$PWD\images\gallery\gallery-$i.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $gb.Dispose()
    $b.Dispose()
}

Write-Host "Created campus & gallery photos successfully."
