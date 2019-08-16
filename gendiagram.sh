#!/bin/sh
set -e
D2UML=d2uml/d2uml
mkdir -p model
(
    echo "@startuml"
    echo "hide empty attributes"
    echo "hide empty methods"
    echo
    find src -xtype d |while read dir
    do
        mkdir -p model/"$dir" 2>/dev/null
        $D2UML "$dir"/*.d > model/"$dir"/Classes.uml
        path=$(echo "$dir" |sed -e 's@^src/@@' -e 's@/@.@g')
        echo "package \"$path\" {"
        echo "    !include $dir/Classes.uml"
        echo "}"
    done
    find src -name \*.d |\
    while read file
    do
        path=$(echo "$file" |sed -e 's@^src/@@' -e 's@/[^/]*\.d$@@' -e 's@/@.@g')
        egrep '(class|interface)' "$file" |\
        sed -e 's/^\(class\|interface\) //' |\
        grep ':' |\
        while read class
        do
            base=$(echo "$class" |sed -e 's/ *:.*//')
            parents=$(echo "$class" |sed -e 's/.*: //' -e 's/, /\n/g')
            echo "$parents" |while read parent
            do
                echo "$parent <|-- $base"
            done
        done
    done
    grep 'M,gold' $(find model/ -name Classes.uml) -Rh |\
    sed -e 's/^class //' -e 's/ .*//' |\
    while read module
    do
        echo "remove $module"
    done
    echo "@enduml"
) > model/ClassDiagram.uml
plantuml model/ClassDiagram.uml
