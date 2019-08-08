# Helper function for color printing
function color(code, string) {
  if (colors == 1) {
    return "\033[38;5;"code"m"string"\033[0m"
  } else {
    return string
  }
}

# Bold version of a color
function bold(code) { return code";1" }

BEGIN {
  NOW = systime()
}

{
  # Last modification date coloring (shades of white, darker is older)
  time = NOW - $1
       if (time <    7200) { date_color = 256 } # modified in the last 2 hours
  else if (time <  604800) { date_color = 247 } # modified in the last week
  else if (time < 7776000) { date_color = 240 } # modified in the last 3 months
  else                     { date_color = 237 } # not modified for 3 months

  # File or directory size coloring
  size = $6
  if (size == -1) { $5 = "" } # Hide empty directory overhead to reduce clutter
       if (size <        1024) { size_color =  14 } # <=  1 KB, blue
  else if (size <       32768) { size_color = 118 } # <= 32 KB, green
  else if (size <     1048576) { size_color = 226 } # <=  1 MB, yellow
  else if (size <    33554432) { size_color = 209 } # <= 32 MB, orange
  else if (size <  1073741824) { size_color =   9 } # <=  1 GB, red
  else if (size < 17179869184) { size_color = 124 } # <= 16 GB, dark red
  else                         { size_color =  92 } # >  16 GB, purple

  type = $3
  runnable = substr($4, 4, 1)
  name_color = 256 # White
       if (type     == "directory"    ) { name_color = bold( 33) } # Dark blue
  else if (type     == "symbolic link") { name_color = bold( 92) } # Purple
  else if (type     == "fifo"         ) { name_color = bold(226) } # Yellow
  else if (type     == "socket"       ) { name_color = bold(118) } # Green
  else if (runnable == "x"            ) { name_color = bold(  9) } # Red

  printf color(date_color, substr($2, 1, 16))" "        # Date
  if (size > -2) printf color(size_color, "%5s")" ", $5 # Size if at least one
  printf color(name_color, $7)                          # Filename
  if ($8) printf " -> "color(bold(208), $8)             # Symbolic link target
  print ""                                              # Newline
}
