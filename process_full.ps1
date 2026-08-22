Add-Type -AssemblyName System.Drawing;
$img = [System.Drawing.Image]::FromFile('C:\Users\Matias\Documents\NeuroHandMobile\assets\logo_kinesis.png');
$bmp = new-object System.Drawing.Bitmap($img);
$img.Dispose();

$w = $bmp.Width;
$h = $bmp.Height;

# Make exact white transparent
$bmp.MakeTransparent([System.Drawing.Color]::White);

# Make near-white transparent as well
for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
        $c = $bmp.GetPixel($x, $y);
        if ($c.R -gt 240 -and $c.G -gt 240 -and $c.B -gt 240) {
            $bmp.SetPixel($x, $y, [System.Drawing.Color]::Transparent);
        }
    }
}

$bmp.Save('C:\Users\Matias\Documents\NeuroHandMobile\assets\logo_kinesis_transparent_full.png', [System.Drawing.Imaging.ImageFormat]::Png);
$bmp.Dispose();
