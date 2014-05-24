#!/bin/bash

if [ ! -f "$1" ]; then
    echo "$0 mediathek.conf"
    exit 1
fi

conf="$1"

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

    for folge in $(curl -s "$b/?docId=$d&pageId=$p&goto=3" | grep -o '/Folge[^"]*' | sed 's/\&amp;/\&/g'); do
        f="${folge/\/Folge-}"
        f="${f/\?*}"
        f="$(echo "$f" | sed 's/-$//')"
        pf="$(echo "$f" | tr "-" " ")"
        save="$drop/$pf.mp4"

        curl -s $b/$folge | sed 's,<source,\'$'\n''&,g' | awk '/data-quality="[SML]"/{split($2,d,"\""); split($3,u,"\""); c[d[2]]++; print d[2] c[d[2]],u[2]}' | while read q u; do
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
                # get metadata
                fn="${f/-*}"
                tmp2=$(mktemp -t mediathekXXXXXX)
                artwork=$(mktemp -t mediathekXXXXXX)
                curl -so "$tmp2" "$(printf "$m" "$fn")"
                curl -so "$artwork" "$(sed -n "s/^<meta property=\"og:image\" content=\"\(.*\)\" \/>/\1/p" "$tmp2" | sed "s/\"/\&quot;/g")"
                if [ $? -ne 0 ]; then
                    m_art=""
                else
                    m_art="--artwork $artwork"
                fi
                m_title="${pf/$fn }"
                m_show="$s"
                m_season="0"
                m_ep="$fn"
                m_year="$(grep SENDETERMIN "$tmp2" | sed -n "s/^.* \([0-3][0-9]\)\.\([01][0-9]\)\.\([12][0-9]\) .*$/20\3-\2-\1/p")"
                m_desc="$(sed -n "s/^<meta name=\"description\" content=\"\(.*\)\" \/>/\1/p" "$tmp2" | sed "s/\"/\&quot;/g")"

                $ap "$tmp" -o "$droptmp/$fn.mp4" --stik "TV Show" --title "$m_title" --TVShowName "$m_show" --TVSeasonNum "$m_season" --TVEpisodeNum "$m_ep" --year "$m_year" --description "$m_desc" $m_art > /dev/null
                mv "$droptmp/$fn.mp4" "$save"
                rm -f $tmp2 $artwork
            fi
            rm -f "$tmp"
        done
    done
done

rm -f "$run"
