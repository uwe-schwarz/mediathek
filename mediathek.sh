#!/bin/bash

conf="${1:-~/.mediathek.conf}"

df="%F-%T"
max=5

declare -a sendung docid pageid base

. $conf

# check if already running
if [ -e "$run" ]; then
    now=$(date +%s)
    gone=$[now - 18000] # 5 hours ago
    if [ $(stat -f %m "$run") -lt $gone ]; then
        rm -f "$run"
    else
echo "$(date +$df) anthr" >> "$log" # another instance running
        exit
    fi
fi

touch "$run"

for ((n=0;n<${#sendung[@]};n++)); do
    s=${sendung[$n]}
    b=${base[$n]}
    d=${docid[$n]}
    p=${pageid[$n]}
    m=${nfo[$n]}
    r=${runtime[$n]:-0}

    for folge in $(curl -s "$b/?docId=$d&pageId=$p" | grep -o '/Folge[^"]*' | sed 's/\&amp;/\&/g'); do
        f="${folge/\/Folge-}"
        f="${f/\?*}"
        f="$(echo "$f" | sed 's/-$//')"
        pf="$(echo "$f" | tr "-" " ")"
        save="$sbase/$s/$pf.mp4"
        meta="$sbase/$s/$pf.nfo"

        curl -s $b/$folge | sed 's,<source,\n&,g' | awk '/data-quality="[SML]"/{split($2,d,"\""); split($3,u,"\""); c[d[2]]++; print d[2] c[d[2]],u[2]}' | while read q u; do
            grep -q " down  $q $f" "$log" && continue
            # q = S1, M1, L1, L2
            if [ "$q" != "L2" ]; then
                continue
            fi
            tmp=$(mktemp -t mediathekXXXXXX)
            c=0
            false
            while [ $? -ne 0 -a $c -lt $max ]; do
                (( c++ ))
                curl -so "$tmp" "$u"
            done
            if [ $? -eq 0 ]; then
echo "$(date +$df) down  $q $f" >> "$log"
                mv "$tmp" "$save" 2>/dev/null
                chmod 644 "$save"
                # get metadata
                if [ "$m" != "" ]; then
                    fn="${f/-*}"
                    curl -so "$tmp" "$(printf "$m" "$fn")"
                    printf "<episodedetails>\n" >> "$meta"
                    printf "<title>%s</title>\n" "${pf/$fn }" >> "$meta"
                    printf "<showtitle>%s</showtitle>\n" "$s" >> "$meta"
                    printf "<season>0</season>\n" >> "$meta"
                    printf "<episode>%d</episode>\n" "$fn" >> "$meta"
                    printf "<aired>%s</aired>\n" "$(grep SENDETERMIN "$tmp" | sed -n "s/^.* \([0-3][0-9]\)\.\([01][0-9]\)\.\([12][0-9]\) .*$/20\3-\2-\1/p")" >> "$meta"
                    printf "<plot>%s</plot>\n" "$(sed -n "s/^<meta name=\"description\" content=\"\(.*\)\" \/>/\1/p" "$tmp" | sed "s/\"/\&quot;/g")" >> "$meta"
                    printf "<runtime>%d</runtime>\n" "$r" >> "$meta"
                    printf "<thumb>%s</thumb>\n" "$(sed -n "s/^<meta property=\"og:image\" content=\"\(.*\)\" \/>/\1/p" "$tmp" | sed "s/\"/\&quot;/g")" >> "$meta"
                    printf "</episodedetails>\n" >> "$meta"
                fi
            fi
            rm -f "$tmp"
        done
    done
done

rm -f "$run"
