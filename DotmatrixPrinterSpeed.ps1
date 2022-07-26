write-host "CPS simulator : Ever wonder how fast 130 CPS was for old printers?" -BackgroundColor DarkBlue -ForegroundColor Yellow

$cps = 130
$width = 132
$delay = 1000.0/ $cps
$tooslow = 0

write-host "$cps CPS rate with a width of $width" -BackgroundColor DarkBlue -ForegroundColor Yellow
write-host ("-"*30) -BackgroundColor DarkBlue -ForegroundColor Yellow


$sentence = "The Apple IIc was released on April 24, 1984, during an Apple-held event called Apple II Forever. With that motto, Apple proclaimed the new machine was proof of the company's long-term commitment to the Apple II series and its users, despite the recent introduction of the Macintosh. The IIc was also seen as the company's response to the new IBM PCjr, and Apple hoped to sell 400,000 by the end of 1984.[4] While essentially an Apple IIe computer in a smaller case, it was not a successor, but rather a portable version to complement it. One Apple II machine would be sold for users who required the expandability of slots, and another for those wanting the simplicity of a plug and play machine with portability in mind.

The machine introduced Apple's Snow White design language, notable for its case styling and a modern look designed by Hartmut Esslinger which became the standard for Apple equipment and computers for nearly a decade. The Apple IIc introduced a unique off-white coloring known as 'Fog', chosen to enhance the Snow White design style. The IIc and some peripherals were the only Apple products to use the 'Fog' coloring.[5] While relatively light-weight and compact in design, the Apple IIc was not a true portable in design as it lacked a built-in battery and display.

The equivalent of five expansion cards were built-in and integrated into the Apple IIc motherboard: [3] An Extended 80 Column Card, two Apple Super Serial Cards, a Mouse Card, and a disk floppy drive controller card. This meant the Apple IIc had 128 KB RAM, 80-column text, and Double-Hi-Resolution graphics built-in and available right out of the box, unlike its older sibling, the Apple IIe. It also meant less of a need for slots, as the most popular peripheral add-on cards were already built-in, ready for devices to be plugged into the rear ports of the machine. The built-in cards were mapped to phantom slots so software from slot-based Apple II models would know where to find them (i.e. mouse to virtual slot 4, serial cards to slot 1 and 2, floppy to slot 6, and so on). The entire Apple Disk II Card, used for controlling floppy drives, had been shrunk down into a single chip called the 'IW' which stood for Integrated Woz Machine."


[int]$delay = $delay
$soundPlayer = New-Object System.Media.SoundPlayer
$soundPlayer.SoundLocation="$PSScriptRoot\dotmatrix.wav"
    
$p=0
foreach ($c in $sentence.ToCharArray()) {
    $tm = Measure-Command {
        $p=$p+1
        if ($c -eq "`n") {
            $p = 0
        
            }
        elseif (($p -gt $width) -and ($c -eq " ")) {
            $c = "`n"
            $p = 0
            }
        write-host  $c   -NoNewline
        # $soundPlayer.PlaySync()
        
        }

    if (($delay - $tm.Milliseconds) -gt 0) {
        start-sleep -Milliseconds ($delay - $tm.Milliseconds)
        }
        else { $tooslow = $tooslow+1 
        }
    
    }

    write-host ("`n`n# the loop was Too Slow : $tooslow of " + $($sentence.ToCharArray()).count)
