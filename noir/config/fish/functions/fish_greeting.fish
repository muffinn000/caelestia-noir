function fish_greeting
    set_color --bold white
    printf '\n  ◈  N O I R'
    set_color brblack
    printf '   /   %s\n\n' (date '+%d.%m.%Y')
    set_color normal
end
