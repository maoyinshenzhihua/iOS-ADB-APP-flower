Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile("e:\zmq\zmq\Assets.xcassets\AppIcon.appiconset\Icon.png")
Write-Host "Width: $($img.Width)"
Write-Host "Height: $($img.Height)"
$img.Dispose()
