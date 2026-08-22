Add-Type -AssemblyName System.Drawing;
$img = [System.Drawing.Image]::FromFile('C:\Users\Matias\Documents\NeuroHandMobile\assets\logo_kinesis.png');
$bmp = new-object System.Drawing.Bitmap($img);
$img.Dispose();

$w = $bmp.Width;
$h = $bmp.Height;
$newH = [int]($h * 0.7);

$croppedBmp = new-object System.Drawing.Bitmap($w, $newH);
$g = [System.Drawing.Graphics]::FromImage($croppedBmp);
$g.DrawImage($bmp, (new-object System.Drawing.Rectangle(0, 0, $w, $newH)), (new-object System.Drawing.Rectangle(0, 0, $w, $newH)), [System.Drawing.GraphicsUnit]::Pixel);
$g.Dispose();

# Make exact white transparent
$croppedBmp.MakeTransparent([System.Drawing.Color]::White);

# Make near-white transparent as well (JPEG artifacts from the prompt)
for ($y = 0; $y -lt $newH; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
        $c = $croppedBmp.GetPixel($x, $y);
        if ($c.R -gt 240 -and $c.G -gt 240 -and $c.B -gt 240) {
            $croppedBmp.SetPixel($x, $y, [System.Drawing.Color]::Transparent);
        }
    }
}

$croppedBmp.Save('C:\Users\Matias\Documents\NeuroHandMobile\assets\logo_kinesis_transparent.png', [System.Drawing.Imaging.ImageFormat]::Png);
$croppedBmp.Dispose();
$bmp.Dispose();
