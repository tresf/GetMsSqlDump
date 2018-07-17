$file = $args[0]
$search = $args[1]
$replace = $args[2]
$new_text = ([System.IO.File]::ReadAllText($file)).Replace($search, $replace)
[System.IO.File]::WriteAllText($file, $new_text)
