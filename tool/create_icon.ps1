param([string]$Destination="$PSScriptRoot\..\windows\runner\resources\app_icon.ico")
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$icon=[Drawing.Bitmap]::new(256,256)
$g=[Drawing.Graphics]::FromImage($icon);$g.SmoothingMode='AntiAlias'
$g.Clear([Drawing.Color]::FromArgb(9,12,19))
$brush=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(180,131,255))
$g.FillEllipse($brush,72,117,114,91)
foreach($rect in @(@(34,76,43,57),@(83,40,42,63),@(135,40,42,63),@(183,76,43,57))){$g.FillEllipse($brush,[int]$rect[0],[int]$rect[1],[int]$rect[2],[int]$rect[3])}
$g.Dispose();$brush.Dispose()
$sizes=@(16,24,32,48,64,128,256);$images=@()
foreach($size in $sizes){$b=[Drawing.Bitmap]::new($size,$size);$g=[Drawing.Graphics]::FromImage($b);$g.InterpolationMode='HighQualityBicubic';$g.DrawImage($icon,0,0,$size,$size);$g.Dispose();$stream=[IO.MemoryStream]::new();$b.Save($stream,[Drawing.Imaging.ImageFormat]::Png);$images+=,$stream.ToArray();$stream.Dispose();$b.Dispose()}
$writer=[IO.BinaryWriter]::new([IO.File]::Create([IO.Path]::GetFullPath($Destination)))
try{$writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]7);$offset=118;for($i=0;$i -lt 7;$i++){$n=$sizes[$i];if($n -eq 256){$n=0};$writer.Write([byte]$n);$writer.Write([byte]$n);$writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$images[$i].Length);$writer.Write([uint32]$offset);$offset+=$images[$i].Length};foreach($bytes in $images){$writer.Write([byte[]]$bytes)}}finally{$writer.Dispose();$icon.Dispose()}
