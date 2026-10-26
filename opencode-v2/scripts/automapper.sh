#!/bin/sh
# AutoMapper replaced (the skills automapper and mapster), by Mapperly (recommended: the mappings generated at build
# time, plain C# with no runtime package and no reflection, a member forgotten fails the build) or by Mapster (the
# closest to AutoMapper: the same model at run time, IMapper and its calls kept, checked by a test). What Qwen should
# not work out by hand, done the same way every time.
#   inventory [<folder>]     read only: the AutoMapper packages and their version, Mapperly or Mapster when there; each
#                            profile (in the order to replace them: the simplest first), each of its maps
#                            (CreateMap<Source, Destination>, its line, the options it uses); the projects to set up; the
#                            converters and resolvers (and whether they take services); the global settings that change
#                            every map (naming conventions, null collections, value transformers…); where the code maps
#                            (Map<T>, a map onto an existing object, ProjectTo, the runtime type forms, IMapper injected),
#                            registers (AddAutoMapper) and tests AutoMapper (AssertConfigurationIsValid, Mock<IMapper>);
#                            what scaffold leaves by hand for each target; the facts of the choice of the target; the plan.
#   setup [--mapster] <project>
#                            once the developer agreed. Mapperly: Riok.Mapperly in the project (compile time only:
#                            ExcludeAssets runtime, PrivateAssets all; Directory.Packages.props when versions are
#                            central), the diagnostics of a mapping left incomplete or ambiguous as errors
#                            (Mapperly.globalconfig), and MapperDefaults.cs, the rules of every mapper of the project, as
#                            AutoMapper mapped; C# 9 at least (LangVersion latest for a netstandard or .NET Framework
#                            target without one). Mapster: Mapster and Mapster.DependencyInjection, and MapsterSetup.cs
#                            (the rules of every map as AutoMapper mapped, AddMapsterMaps in place of AddAutoMapper, the
#                            strict configuration of the test that replaces AssertConfigurationIsValid). Then the build;
#                            a build that fails: every file put back as it was, nothing changed.
#   scaffold [--mapster] <profile file>
#                            each map of the profile translated, next to it (same namespace), never written over an
#                            existing file; what the script does not translate quoted above its code with a TODO line.
#                            Mapperly: <Name>Mapper.cs, a static partial class (an instance class, their services in its
#                            constructor, when resolvers of the profile take some), a method per map (To<Destination>,
#                            the way back of a ReverseMap To<Source>, ApplyTo onto an existing object, ProjectTo<D> for
#                            a projection), the code of BeforeMap, AfterMap and Condition around the generated one.
#                            Mapster: <Name>Register.cs, an IRegister, a NewConfig per map (Condition into IgnoreIf: the
#                            member left as it is, as AutoMapper did).
#   helpers <test project>   the helpers of the snapshot tests of the maps, once: Mapping/MappingSnapshot.cs of the test
#                            project (MappingSample.Create<T>, a source whose every member has a value of its own, and
#                            MappingSnapshot.Verify, what a map gives compared with its golden file); never written over.
#   record <test project> [<filter>]
#                            the golden files of the snapshot tests (Mapping/Snapshots/*.json), written from what
#                            AutoMapper gives (MAPPING_RECORD=1, the tests of the filter, FullyQualifiedName~Mapping by
#                            default); a golden file there already is never written again: it is the contract the
#                            new mapping must meet (a committed one edited since: STOP). Tests that fail: nothing
#                            recorded.
#   switch [<folder>]        Mapster, the last step: the code that used AutoMapper onto Mapster, what is sure rewritten
#                            (using AutoMapper -> MapsterMapper, its QueryableExtensions -> Mapster; ProjectTo ->
#                            ProjectToType, ConfigurationProvider -> Config; AddAutoMapper(typeof(XProfile)) ->
#                            AddMapsterMaps(typeof(XRegister)); new MapperConfiguration(cfg => cfg.AddProfile<X>()) ->
#                            MapsterSetup.Configure(...), CreateMapper -> new Mapper, AssertConfigurationIsValid ->
#                            Compile), the rest left as it was and listed; the profiles and resolvers left out (they
#                            leave with AutoMapper). The calls of IMapper and the test doubles of IMapper do not change.
#   check [<folder>]         read only: what is left of AutoMapper, each with its file and line (a quote of a map left in
#                            a comment included); "AUTOMAPPER: GONE" when nothing is left (the Markdown documentation
#                            excepted), exit 1 otherwise.
# Output: "INVENTORY:", "PACKAGE:", "PROFILE:", "MAP:", "PROJECTS:", "CONVERTER:", "GLOBAL:", "CALL:", "REGISTRATION:",
# "TEST:", "TRANSLATED:", "TARGET:", "PLAN:" (inventory); "SETUP:" (setup); "SCAFFOLD:", "WRITTEN:"/"KEPT:",
# "METHOD:" (Mapperly), "NEXT:" (scaffold); "WRITTEN:"/"KEPT:", "HELPERS:" (helpers); "RECORDED:", "RECORD:" (record);
# "SWITCHED:", "LEFT:", "SWITCH:" (switch); "LEFT:" lines and "AUTOMAPPER: GONE" or "AUTOMAPPER: <n> place(s) left"
# (check); "STOP:" when something is wrong.
# Usage: automapper.sh inventory [<folder>] | setup [--mapster] <project> | scaffold [--mapster] <profile file>
#        | helpers <test project> | record <test project> [<filter>] | switch [<folder>] | check [<folder>]

LC_ALL=C
export LC_ALL
here=$(cd "$(dirname "$0")" && pwd)
start=$PWD
action=$1
[ $# -gt 0 ] && shift
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "STOP: not a git repository"; exit 1; }
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/automapper.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
MAPPERLY_DEFAULT=4.3.1
MAPSTER_DEFAULT=10.0.13
# The diagnostics of Mapperly that become errors: a target member without source (RMG012), a source member left out of
# a method that asks for all of them (RMG020), an ignore or a mapping that names nothing or both (RMG004, RMG021, RMG049,
# RMG050), enums that do not match (RMG003, RMG037, RMG038), two user methods for the same types without a default
# (RMG060), an object mapping that maps nothing (RMG066), a Use whose method has other types (RMG072, RMG073), a method a
# projection cannot inline (RMG068: the query would load whole rows)
STRICT="RMG003 RMG004 RMG012 RMG020 RMG021 RMG037 RMG038 RMG049 RMG050 RMG060 RMG066 RMG068 RMG072 RMG073"

# a path given from the folder of the call, made relative to the root of the repository
from_root() {
  case "$1" in
    "") return 0 ;;
    /*) p=$1 ;;
    *) p="$start/$1" ;;
  esac
  if [ -d "$p" ]; then
    p=$(cd "$p" && pwd)
  elif [ -d "$(dirname "$p")" ]; then
    p="$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
  fi
  [ "$p" = "$root" ] && { printf '.'; return 0; }
  printf '%s' "${p#"$root"/}"
}

# the C# files of the repository, those not committed yet included
cs_files() {
  git ls-files --cached --others --exclude-standard ${1:+"$1"} | grep -E '\.cs$' | sort -u
}

# the project of a file: the nearest folder above it with a .csproj
project_of() {
  d=$(dirname "$1")
  while :; do
    p=$(find "$d" -maxdepth 1 -name '*.csproj' 2>/dev/null | sort | head -n 1)
    [ -n "$p" ] && { printf '%s\n' "$p" | sed 's:^\./::'; return 0; }
    [ "$d" = . ] || [ "$d" = / ] && return 0
    d=$(dirname "$d")
  done
}

# The statements of a C# file that call CreateMap: "<first line>\t<last line>\t<the statement on one line>", from
# CreateMap to the ";" that ends it (parentheses and braces counted, strings and comments skipped)
statements() {
  awk '
    { text = text $0 "\n" }
    END {
      n = length(text); line = 1; i = 1
      while (i <= n) {
        c = substr(text, i, 1)
        if (c == "\n") { line++; i++; continue }
        if (c == "/" && substr(text, i + 1, 1) == "/") { while (i <= n && substr(text, i, 1) != "\n") i++; continue }
        if (c == "\"") { i = skip_string(i); continue }
        if (substr(text, i, 9) == "CreateMap" && (i == 1 || substr(text, i - 1, 1) !~ /[A-Za-z0-9_]/) && substr(text, i + 9, 1) ~ /[<(]/) {
          start = line; depth = 0; out = ""; j = i
          while (j <= n) {
            d = substr(text, j, 1)
            if (d == "\"") { k = skip_string(j); out = out substr(text, j, k - j); j = k; continue }
            if (d == "/" && substr(text, j + 1, 1) == "/") { while (j <= n && substr(text, j, 1) != "\n") j++; continue }
            if (d == "\n") { line++; out = out " "; j++; continue }
            if (d == "(" || d == "{") depth++
            if (d == ")" || d == "}") { depth--; if (depth < 0) break }
            if (d == ";" && depth == 0) break
            out = out d; j++
          }
          gsub(/[ \t]+/, " ", out)
          printf "%d\t%d\t%s\n", start, line, out
          i = j + 1; continue
        }
        i++
      }
    }
    function skip_string(p,   q, ch) {
      q = p + 1
      while (q <= n) { ch = substr(text, q, 1); if (ch == "\\") { q += 2; continue } if (ch == "\"") return q + 1; if (ch == "\n") line++; q++ }
      return q
    }' "$1"
}

# The source and destination types of a statement: "<source>\t<destination>" (CreateMap<A, B> or CreateMap(typeof(A), typeof(B)))
types_of() {
  printf '%s\n' "$1" | awk '
    {
      s = $0
      if (match(s, /^CreateMap</)) {
        i = RLENGTH + 1; depth = 1; arg = ""; n = 0
        while (i <= length(s) && depth > 0) {
          c = substr(s, i, 1)
          if (c == "<") depth++
          if (c == ">") { depth--; if (depth == 0) break }
          if (c == "," && depth == 1) { a[++n] = arg; arg = ""; i++; continue }
          arg = arg c; i++
        }
        a[++n] = arg
        gsub(/^ +| +$/, "", a[1]); gsub(/^ +| +$/, "", a[2])
        printf "%s\t%s\n", a[1], a[2]
      } else if (match(s, /typeof\([^)]*\)[ ]*,[ ]*typeof\([^)]*\)/)) {
        t = substr(s, RSTART, RLENGTH); gsub(/typeof\(|\)/, "", t); split(t, b, /[ ]*,[ ]*/)
        printf "%s\t%s\n", b[1], b[2]
      } else print "?\t?"
    }'
}

# The options a statement uses, with their count: "ForMember×3, Ignore×1, ReverseMap"
options_of() {
  printf '%s\n' "$1" | awk '
    {
      n = split("ForMember MapFrom Ignore ReverseMap BeforeMap AfterMap ConvertUsing ConstructUsing Include IncludeBase IncludeAllDerived IncludeMembers Condition PreCondition NullSubstitute ForCtorParam ForPath MaxDepth PreserveReferences UseDestinationValue ForAllMembers ForSourceMember ValidateMemberList AddTransform DisableCtorValidation ExplicitExpansion As", names, " ")
      out = ""
      for (k = 1; k <= n; k++) {
        s = $0; cnt = 0
        while (match(s, "\\." names[k] "[<(]")) { cnt++; s = substr(s, RSTART + RLENGTH) }
        if (cnt > 0) out = out (out == "" ? "" : ", ") names[k] (cnt > 1 ? "×" cnt : "")
      }
      if ($0 ~ /MemberList\.(Source|None)/) out = out (out == "" ? "" : ", ") "MemberList"
      if ($0 ~ /MapFrom<|ConvertUsing<|ConvertUsing\(typeof|AfterMap<|BeforeMap</) out = out (out == "" ? "" : ", ") "a resolver/converter/action class"
      print out
    }'
}

# The simple name of a type, for a method: Shop.Dtos.OrderDto -> OrderDto, Page<Order> -> Page
simple_name() {
  printf '%s\n' "$1" | sed -E 's/<.*//; s/.*\.//; s/\?$//'
}

case "$action" in
  inventory|check|setup|scaffold|helpers|record|switch) ;;
  *) echo "STOP: automapper.sh inventory [<folder>] | setup [--mapster] <project> | scaffold [--mapster] <profile file> | helpers <test project> | record <test project> [<filter>] | switch [<folder>] | check [<folder>]"; exit 1 ;;
esac

# ---------- check ----------
if [ "$action" = check ]; then
  folder=$(from_root "$1")
  [ -z "$folder" ] || [ -e "$folder" ] || { echo "STOP: no folder $1"; exit 1; }
  : > "$tmp/left"
  git grep --untracked -n -i -E 'Include="AutoMapper' -- ${folder:+"$folder"} '*.csproj' '*.props' '*.targets' 2>/dev/null | sed 's/^/LEFT: project: /' >> "$tmp/left"
  git grep --untracked -n -E '^[[:space:]]*(global[[:space:]]+)?using[[:space:]]+(static[[:space:]]+)?AutoMapper' -- ${folder:+"$folder"} '*.cs' 2>/dev/null | sed 's/^/LEFT: using: /' >> "$tmp/left"
  git grep --untracked -n -E '(^|[^A-Za-z0-9_])CreateMap[<(]' -- ${folder:+"$folder"} '*.cs' 2>/dev/null | sed 's/^/LEFT: map: /' >> "$tmp/left"
  git grep --untracked -n -E 'AddAutoMapper|MapperConfiguration|ProjectTo<|AssertConfigurationIsValid|\.ConfigurationProvider([^A-Za-z0-9_]|$)' -- ${folder:+"$folder"} '*.cs' 2>/dev/null | sed 's/^/LEFT: configuration or call: /' >> "$tmp/left"
  git grep --untracked -n -E 'I(Value|MemberValue)Resolver<|ITypeConverter<|IValueConverter<|IMappingAction<|ResolutionContext|AutoMapper\.' -- ${folder:+"$folder"} '*.cs' 2>/dev/null |
    grep -v -E '^[^:]*:[0-9]+:[[:space:]]*(global[[:space:]]+)?using[[:space:]]' | sed 's/^/LEFT: type: /' >> "$tmp/left"
  sort -u "$tmp/left" -o "$tmp/left"
  n=$(grep -c . "$tmp/left")
  if [ "$n" -eq 0 ]; then
    echo "AUTOMAPPER: GONE (no package, using, map, configuration, IMapper, resolver or converter of AutoMapper in the code and the projects; the Markdown documentation is not looked at)"
    exit 0
  fi
  cut -c1-240 "$tmp/left"
  echo "AUTOMAPPER: $n place(s) left"
  exit 1
fi

# ---------- inventory ----------
if [ "$action" = inventory ]; then
  folder=$(from_root "$1")
  [ -z "$folder" ] || [ -e "$folder" ] || { echo "STOP: no folder $1"; exit 1; }
  version=$(git grep --untracked -h -o -i -E 'Include="AutoMapper"[^>]*Version="[0-9][^"]*"' -- '*.csproj' '*.props' 2>/dev/null | sed -E 's/.*Version="([^"]*)".*/\1/' | sort -u | head -n 1)
  : > "$tmp/profiles"
  : > "$tmp/maps"
  : > "$tmp/used"
  cs_files "$folder" > "$tmp/files"
  while IFS= read -r f; do
    grep -q -E '(^|[^A-Za-z0-9_])CreateMap[<(]' "$f" 2>/dev/null || continue
    profile=$(grep -o -E 'class[[:space:]]+[A-Za-z0-9_]+[[:space:]]*(\([^)]*\))?[[:space:]]*:[[:space:]]*(AutoMapper\.)?Profile([^A-Za-z0-9_]|$)' "$f" | head -n 1 | sed -E 's/class[[:space:]]+([A-Za-z0-9_]+).*/\1/')
    statements "$f" > "$tmp/st"
    count=0 score=0
    while IFS="$(printf '\t')" read -r first _ text; do
      count=$((count + 1))
      t=$(types_of "$text")
      src=$(printf '%s' "$t" | cut -f1) dst=$(printf '%s' "$t" | cut -f2)
      opts=$(options_of "$text")
      printf '%s\n' "$opts" | tr ',' '\n' | sed -E 's/^ +//; s/×[0-9]+$//' | grep . >> "$tmp/used"
      # the options that need more than an attribute per member
      special=$(printf '%s\n' "$opts" | grep -o -E 'BeforeMap|AfterMap|ConvertUsing|ConstructUsing|Include[A-Za-z]*|Condition|PreCondition|ForPath|MaxDepth|PreserveReferences|AddTransform|a resolver/converter/action class' | grep -c .)
      score=$((score + special))
      printf '%s\t%s:%s\t%s -> %s%s\n' "$f" "$f" "$first" "$src" "$dst" "${opts:+ — $opts}" >> "$tmp/maps"
    done < "$tmp/st"
    printf '%s\t%s\t%s\t%s\n' "$score" "$count" "$f" "${profile:-(no profile class: maps in a configuration)}" >> "$tmp/profiles"
  done < "$tmp/files"
  np=$(grep -c . "$tmp/profiles")
  nm=$(grep -c . "$tmp/maps")
  echo "INVENTORY: $np file(s) with maps, $nm map(s)${version:+, AutoMapper $version}"
  # each AutoMapper package once, with its version (from the project, or from Directory.Packages.props)
  git grep --untracked -h -o -E 'Include="AutoMapper[^"]*"[^>]*' -- '*.csproj' '*.props' 2>/dev/null | sed -E 's/Include="([^"]*)".*Version="([^"]*)".*/\1 \2/; s/Include="([^"]*)".*/\1/' |
    awk '{ if (!($1 in v) || $2 != "") v[$1] = $2 } END { for (k in v) print k (v[k] == "" ? "" : " " v[k]) }' | sort |
    awk '{ printf "%s%s", (NR > 1 ? ", " : "PACKAGE: "), $0 } END { if (NR) print "" }'
  case "$version" in
    1[5-9]*|[2-9][0-9]*) echo "PACKAGE: AutoMapper $version is under a commercial license (since 15.0): its removal ends it" ;;
    [0-9]*) echo "PACKAGE: AutoMapper $version: a free version, with CVE-2026-32933 (high: a deep object graph overflows the stack, denial of service), fixed only in the paid 15.1.1 and 16.1.1: never raise it on the way" ;;
  esac
  mapperly=$(git grep --untracked -l -i -E 'Include="Riok\.Mapperly"' -- '*.csproj' 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')
  [ -n "$mapperly" ] && echo "PACKAGE: Riok.Mapperly already in $mapperly"
  sort -t "$(printf '\t')" -k1,1n -k2,2n -k3,3 "$tmp/profiles" > "$tmp/ordered"
  step=0
  while IFS="$(printf '\t')" read -r score count f name; do
    step=$((step + 1))
    echo "PROFILE: $f — $name — $count map(s)$([ "$score" -gt 0 ] && echo ", $score option(s) beyond an attribute per member") — step $step"
    grep -F "$f	" "$tmp/maps" | cut -f2- | sed 's/^/MAP: /; s/	/ /'
  done < "$tmp/ordered"
  # the projects of the profiles: where Mapperly goes
  cut -f3 "$tmp/ordered" | while IFS= read -r f; do project_of "$f"; done | sort -u > "$tmp/projects"
  if [ -s "$tmp/projects" ]; then
    todo=""
    while IFS= read -r p; do grep -qi 'Include="Riok\.Mapperly"' "$p" || todo="$todo${todo:+ }$p"; done < "$tmp/projects"
    if [ -n "$todo" ]; then
      echo "PROJECTS: $todo (Riok.Mapperly to add, once the developer agreed: automapper.sh setup <each>)"
    else
      echo "PROJECTS: $(tr '\n' ' ' < "$tmp/projects" | sed 's/ $//') (Mapperly already set up)"
    fi
  fi
  # the converters, resolvers and actions: a class each, and whether it takes services (the mapper then is an instance)
  : > "$tmp/converters"
  while IFS= read -r f; do
    grep -n -E 'class[[:space:]]+[A-Za-z0-9_]+.*:[^{]*(IValueResolver|IMemberValueResolver|ITypeConverter|IValueConverter|IMappingAction)<' "$f" 2>/dev/null |
      while IFS=: read -r line text; do
        name=$(printf '%s' "$text" | sed -E 's/.*class[[:space:]]+([A-Za-z0-9_]+).*/\1/')
        kind=$(printf '%s' "$text" | grep -o -E '(IValueResolver|IMemberValueResolver|ITypeConverter|IValueConverter|IMappingAction)<[^{]*' | head -n 1 | sed 's/[[:space:]]*$//')
        services=""
        if printf '%s' "$text" | grep -q -E "class[[:space:]]+${name}[[:space:]]*\\([^)]+\\)" || grep -q -E "(public|internal|protected)[[:space:]]+${name}[[:space:]]*\\([^)]+\\)" "$f"; then
          services=" — takes services in its constructor: its mapper is an instance class, built by dependency injection"
        fi
        echo "CONVERTER: $f:$line $name ($kind)$services"
      done
  done < "$tmp/files" | tee "$tmp/converters"
  git grep --untracked -n -E 'AllowNullCollections|AllowNullDestinationValues|SourceMemberNamingConvention|DestinationMemberNamingConvention|ShouldMapProperty|ShouldMapField|ShouldMapMethod|ShouldUseConstructor|AddGlobalIgnore|ValueTransformers|ForAllMaps|ForAllPropertyMaps|RecognizePrefixes|RecognizePostfixes|RecognizeDestinationPrefixes|RecognizeDestinationPostfixes|ClearPrefixes|ReplaceMemberName|DisableConstructorMapping|EnableNullPropagationForQueryMapping|AddMaps\(|Internal\(\)' -- ${folder:+"$folder"} '*.cs' 2>/dev/null |
    sed -E 's/^([^:]*:[0-9]+):[[:space:]]*(.*)$/GLOBAL: \1 \2 (it changes how every map behaves: the snapshot tests show it, the skill says its equivalent)/' | cut -c1-260
  # where the code maps with AutoMapper: the files that name it, the profiles left out
  cut -f1 "$tmp/maps" | sort -u > "$tmp/mapfiles"
  git grep --untracked -l -E '(^|[^A-Za-z0-9_])IMapper([^A-Za-z0-9_]|$)|using[[:space:]]+AutoMapper|ProjectTo<' -- ${folder:+"$folder"} '*.cs' 2>/dev/null | grep -v -x -F -f "$tmp/mapfiles" > "$tmp/users"
  : > "$tmp/calls"
  if [ -s "$tmp/users" ]; then
    tr '\n' '\0' < "$tmp/users" | xargs -0 grep -n -H -E '\.ProjectTo<|\.Map<|\.Map\(|(^|[^A-Za-z0-9_])IMapper([^A-Za-z0-9_]|$)' 2>/dev/null |
      awk '{
        text = $0; sub(/^[^:]*:[0-9]+:[[:space:]]*/, "", text)
        split($0, f, ":")
        kind = "IMapper"
        if (text ~ /Mock<IMapper>|Substitute\.For<IMapper>/) kind = "a test double of IMapper"
        else if (text ~ /\.ProjectTo</) kind = "ProjectTo (an IQueryable projection)"
        else if (text ~ /\.Map<[^>]*>\(/) kind = "Map<T> (a new object)"
        else if (text ~ /\.Map\([^,()]*,[^,()]*,/) kind = "Map(source, sourceType, destinationType) (the runtime type)"
        else if (text ~ /\.Map\([^,()]*,[^,()]*\)/) kind = "Map(source, destination) (onto an existing object)"
        else if (text ~ /\.Map\(/) kind = "Map(...)"
        else if (text ~ /IMapper[ \t]+[A-Za-z_]+[ \t]*[,)]|\(IMapper[ \t]/) kind = "IMapper injected"
        printf "CALL: %s:%s %s — %s\n", f[1], f[2], kind, substr(text, 1, 120)
      }' > "$tmp/calls"
    cat "$tmp/calls"
  fi
  git grep --untracked -n -E 'AddAutoMapper|new MapperConfiguration' -- ${folder:+"$folder"} '*.cs' 2>/dev/null | sed -E 's/^([^:]*:[0-9]+):[[:space:]]*(.*)$/REGISTRATION: \1 \2/' | cut -c1-220
  git grep --untracked -n -E 'AssertConfigurationIsValid|Mock<IMapper>|Substitute\.For<IMapper>' -- ${folder:+"$folder"} '*.cs' 2>/dev/null | sed -E 's/^([^:]*:[0-9]+):[[:space:]]*(.*)$/TEST: \1 \2/' | cut -c1-220
  # what automapper.sh scaffold leaves to write by hand, by target (a TODO line in the code it writes)
  hand_mapperly="" hand_mapster=""
  while IFS= read -r opt; do
    case "$opt" in
      "a resolver/converter/action class"|IncludeAllDerived|IncludeMembers|UseDestinationValue|As|ExplicitExpansion)
        hand_mapperly="$hand_mapperly${hand_mapperly:+, }$opt" hand_mapster="$hand_mapster${hand_mapster:+, }$opt" ;;
      MaxDepth|PreserveReferences|AddTransform|ForAllMembers)
        hand_mapperly="$hand_mapperly${hand_mapperly:+, }$opt" ;;
    esac
  done < "$(sort -u "$tmp/used" > "$tmp/used.u"; echo "$tmp/used.u")"
  grep -q -E '<> ->|-> [^ ]*<>' "$tmp/maps" && hand_mapperly="$hand_mapperly${hand_mapperly:+, }an open generic"
  echo "TRANSLATED: automapper.sh scaffold translates each map, for Mapperly or for Mapster; by hand (a TODO line): ${hand_mapperly:-nothing} (Mapperly), ${hand_mapster:-nothing} (Mapster)"
  # the facts of the choice of the target, for the question of /go
  n_calls=$(grep -c -E ' (Map<T>|Map\(source, destination\)|Map\(source, sourceType|Map\(\.\.\.\))' "$tmp/calls")
  n_proj=$(grep -c ' ProjectTo ' "$tmp/calls")
  n_inject=$(grep -c 'IMapper injected' "$tmp/calls")
  n_mocks=$(grep -c 'a test double of IMapper' "$tmp/calls")
  n_runtime=$(grep -c 'the runtime type' "$tmp/calls")
  n_ba=$(cut -f3 "$tmp/maps" | grep -o -E '(BeforeMap|AfterMap|Condition|PreCondition)(×[0-9]+)?' | awk -F'×' '{ n += ($2 == "" ? 1 : $2) } END { print n + 0 }')
  n_res=$(grep -c 'takes services' "$tmp/converters" 2>/dev/null)
  n_items=$(git grep --untracked -h -E 'opts\.Items|\.Items\[|IMappingOperationOptions|[A-Za-z]\.Mapper\.Map' -- ${folder:+"$folder"} '*.cs' 2>/dev/null | grep -c .)
  n_global=$(git grep --untracked -c -E 'AllowNullCollections|AllowNullDestinationValues|MemberNamingConvention|ShouldMap|AddGlobalIgnore|ValueTransformers|ForAllMaps|ForAllPropertyMaps|Recognize[A-Za-z]*fixes|ReplaceMemberName' -- ${folder:+"$folder"} '*.cs' 2>/dev/null | awk -F: '{ n += $NF } END { print n + 0 }')
  echo "TARGET: Mapperly (recommended: generated at build time, every member checked by the build, no package at run time, the fastest): $n_calls call(s) of IMapper and $n_proj ProjectTo rewritten into calls of the mappers, $n_inject constructor(s) without IMapper, $n_mocks test double(s) of IMapper rewritten; $n_ba BeforeMap, AfterMap or Condition into methods written by scaffold; $n_res resolver(s) with services into an instance mapper; $n_runtime map(s) of runtime types and $n_items use(s) of Items or of the mapper inside a map to redesign"
  echo "TARGET: Mapster (the closest to AutoMapper: the same model at run time, checked by a test): the $n_calls call(s), the $n_inject constructor(s) and the $n_mocks test double(s) unchanged (automapper.sh switch: the usings, ProjectTo into ProjectToType, the registration); BeforeMap, AfterMap and Condition kept as they are; $n_items use(s) of Items or of the mapper inside a map and $n_global global setting(s) with their equivalent in Mapster; the package Mapster at run time"
  if [ "$nm" -gt 0 ]; then
    echo "PLAN: the developer's answer first (« Cible » : Mapperly, Mapster or by hand; then automapper.sh setup [--mapster] <each project of the PROJECTS line>, a first commit); then one profile per step in the order of the PROFILE lines, each « (filet d'abord) » (the snapshot tests of its maps, recorded on AutoMapper: automapper.sh helpers and record) and « (s'appuyer sur le skill automapper) » (automapper.sh scaffold [--mapster] <profile file>, its TODO lines; Mapperly: its callers too); the last step removes AutoMapper (Mapster: automapper.sh switch first; the profiles, resolvers, AddAutoMapper, its tests, the packages) until automapper.sh check says AUTOMAPPER: GONE"
  else
    echo "PLAN: no map of AutoMapper; automapper.sh check says what may be left (packages, registrations, IMapper)"
  fi
  exit 0
fi

# ---------- setup ----------
cache_best() {
  cache=${NUGET_PACKAGES:-$HOME/.nuget/packages}
  for d in "$cache/${1:-riok.mapperly}"/*; do [ -d "$d" ] && basename "$d"; done | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
    awk -F. '{ printf "%09d%09d%09d %s\n", $1, $2, $3, $0 }' | sort | tail -n 1 | cut -d' ' -f2
}
newer() {
  # the newer of two versions
  printf '%s\n%s\n' "$1" "$2" | grep . | awk -F. '{ printf "%09d%09d%09d %s\n", $1, $2, $3, $0 }' | sort | tail -n 1 | cut -d' ' -f2
}
# the Directory.<name>.props files above a folder, the nearest first
props_above() {
  d=$1
  while :; do
    [ -f "$d/Directory.$2.props" ] && printf '%s\n' "$d/Directory.$2.props" | sed 's:^\./::'
    [ "$d" = . ] || [ "$d" = / ] && return 0
    d=$(dirname "$d")
  done
}
central_props() {
  p=$(props_above "$1" Packages | head -n 1)
  [ -n "$p" ] || return 0
  if grep -qi '<ManagePackageVersionsCentrally>[[:space:]]*true' "$p" || props_above "$1" Build | xargs grep -qsi '<ManagePackageVersionsCentrally>[[:space:]]*true'; then
    printf '%s\n' "$p"
  fi
}

# add_package <id> <version> [<attributes>]: its PackageReference in the project, its version in Directory.Packages.props
# when versions are central; nothing when the project has it already
add_package() {
  grep -qi "Include=\"$1\"" "$csproj" && return 1
  if [ -n "$props" ]; then
    grep -qi "<PackageVersion[^>]*Include=\"$1\"" "$props" ||
      awk -v id="$1" -v v="$2" '
        function line() { return "    <PackageVersion Include=\"" id "\" Version=\"" v "\" />" }
        !done && /<PackageVersion / { seen = 1 }
        !done && seen && /<\/ItemGroup>/ { print line(); done = 1 }
        !done && /<\/Project>/ { print "  <ItemGroup>"; print line(); print "  </ItemGroup>"; done = 1 }
        { print }' "$props" > "$tmp/props.new" && cat "$tmp/props.new" > "$props"
    ref="    <PackageReference Include=\"$1\"$3 />"
  else
    ref="    <PackageReference Include=\"$1\" Version=\"$2\"$3 />"
  fi
  awk -v ref="$ref" '
    !done && /<PackageReference / { seen = 1 }
    !done && seen && /<\/ItemGroup>/ { print ref; done = 1 }
    !done && /<\/Project>/ { print "  <ItemGroup>"; print ref; print "  </ItemGroup>"; print ""; done = 1 }
    { print }' "$csproj" > "$tmp/csproj.new" && cat "$tmp/csproj.new" > "$csproj"
  return 0
}

if [ "$action" = setup ]; then
  mode=mapperly
  [ "$1" = --mapster ] && { mode=mapster; shift; }
  target=$(from_root "$1")
  [ -n "$target" ] || { echo "STOP: automapper.sh setup [--mapster] <the project of the profiles, or its folder>"; exit 1; }
  case "$target" in
    *.csproj) csproj=$target ;;
    *) csproj=$(find "$target" -maxdepth 1 -name '*.csproj' 2>/dev/null | sort | head -n 1) ;;
  esac
  [ -n "$csproj" ] && [ -f "$csproj" ] || { echo "STOP: no .csproj in $1"; exit 1; }
  csproj=$(printf '%s' "$csproj" | sed 's:^\./::')
  grep -q '<Project Sdk=' "$csproj" || { echo "STOP: $csproj is not an SDK-style project: PackageReference and the generators of Roslyn need one"; exit 1; }
  project=$(dirname "$csproj")
  props=$(central_props "$project")
  config="$project/Mapperly.globalconfig"
  # the files it changes, kept to put them back when the build fails
  for f in "$csproj" $props; do cp "$f" "$tmp/$(printf '%s' "$f" | tr '/' '_')"; done
  wrote=""
  undo() {
    for f in "$csproj" $props; do cp "$tmp/$(printf '%s' "$f" | tr '/' '_')" "$f"; done
    for f in $wrote; do rm -f "$f"; done
  }
  if [ "$mode" = mapster ]; then
    v=$(newer "$(cache_best mapster)" "$MAPSTER_DEFAULT")
    # Mapster.DependencyInjection needs Microsoft.Extensions.DependencyInjection.Abstractions 9.0.0 or more (net8.0
    # included): a project that references an older one directly fails its restore (NU1605, a downgrade)
    low=$(git grep --untracked -n -i -E '(Include|Update)="Microsoft\.Extensions\.DependencyInjection\.Abstractions"[^>]*Version="[0-8]\.' -- '*.csproj' '*.props' '*.targets' 2>/dev/null |
      cut -d: -f1,2 | tr '\n' ' ' | sed 's/ $//')
    if [ -n "$low" ]; then
      echo "STOP: Mapster.DependencyInjection $v needs Microsoft.Extensions.DependencyInjection.Abstractions 9.0.0 or more (it runs on net8.0 too); $low reference(s) an older version: the restore would fail (NU1605). Raise it there once the developer agreed, then automapper.sh setup --mapster again; nothing changed"
      exit 1
    fi
    if add_package Mapster "$v"; then
      add_package Mapster.DependencyInjection "$v"
      done_what="Mapster $v and Mapster.DependencyInjection $v added to $csproj${props:+ (their version in $props)}"
    else
      add_package Mapster.DependencyInjection "$v" || :
      done_what="Mapster already in $csproj"
    fi
    setup_file=$(git grep --untracked -l -E 'static class MapsterSetup' -- '*.cs' 2>/dev/null | head -n 1)
    if [ -z "$setup_file" ]; then
      setup_ns=$(sed -n -E 's/.*<RootNamespace>([^<]*)<.*/\1/p' "$csproj" | head -n 1)
      [ -n "$setup_ns" ] || setup_ns=$(basename "$csproj" .csproj | tr -- '-' '_')
      setup_file="$project/MapsterSetup.cs"
      # AllowNullCollections = true somewhere: a null list stays null, as AutoMapper then did
      allownull=0 lists="a null list mapped to an empty one"
      if git grep --untracked -q -E 'AllowNullCollections[[:space:]]*=[[:space:]]*true' -- '*.cs' 2>/dev/null; then
        allownull=1 lists="a null list left null (AllowNullCollections = true)"
      fi
      awk -v ns="$setup_ns" -v lists="$lists" -v allownull="$allownull" '
        { gsub(/__NAMESPACE__/, ns); gsub(/__LISTS__/, lists) }
        allownull && /EmptyCollectionIfNull/ { prev = prev ";"; next }
        NR > 1 { print prev }
        { prev = $0 }
        END { print prev }' > "$setup_file" <<'EOF'
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using Mapster;
using MapsterMapper;
using Microsoft.Extensions.DependencyInjection;

namespace __NAMESPACE__;

// Mapster as AutoMapper mapped (written by automapper.sh setup --mapster; the application owns it)
public static class MapsterSetup
{
    private static readonly ConditionalWeakTable<TypeAdapterConfig, HashSet<Assembly>> Scanned = new();

    // The rules of every map, as AutoMapper: member names compared without case, enums by name,
    // __LISTS__.
    // Then the IRegister classes of the assemblies, each once (a second host of the tests does not configure them
    // again). strict: a target member without source nor Ignore fails Compile(), as the validation of AutoMapper did
    // (the test of the Registers), never at run time, where AutoMapper left such a member as it was
    public static TypeAdapterConfig Configure(TypeAdapterConfig config, bool strict, params Assembly[] assemblies)
    {
        lock (Scanned)
        {
            if (!Scanned.TryGetValue(config, out var done))
            {
                config.Default
                    .NameMatchingStrategy(NameMatchingStrategy.IgnoreCase)
                    .EnumMappingStrategy(EnumMappingStrategy.ByName)
                    .AddDestinationTransform(DestinationTransform.EmptyCollectionIfNull);
                config.RequireDestinationMemberSource = strict;
                Scanned.Add(config, done = new HashSet<Assembly>());
            }
            var fresh = assemblies.Where(done.Add).ToArray();
            if (fresh.Length > 0)
                config.Scan(fresh);
        }
        return config;
    }

    // In place of the registration of AutoMapper: the maps of the assemblies of these types, IMapper with the
    // services of its scope (MapContext.Current.GetService<T>() in a map)
    public static IServiceCollection AddMapsterMaps(this IServiceCollection services, params Type[] markers)
    {
        var assemblies = markers.Select(t => t.Assembly).Distinct().ToArray();
        services.AddSingleton(Configure(TypeAdapterConfig.GlobalSettings, false, assemblies));
        services.AddScoped<IMapper, ServiceMapper>();
        return services;
    }
}
EOF
      wrote="$wrote $setup_file"
      setup_what="$setup_file written (the rules of AutoMapper, AddMapsterMaps in place of AddAutoMapper, Configure(strict: true) for the test that replaces AssertConfigurationIsValid)"
    else
      setup_what="$setup_file kept"
    fi
    out=$(sh "$here/build-test.sh" --build-only "$csproj" 2>&1)
    if ! printf '%s\n' "$out" | grep -q '^BUILD: OK'; then
      undo
      printf '%s\n' "$out" | tail -n 15
      echo "STOP: the build of $csproj fails with Mapster $v: every file put back, nothing changed"
      exit 1
    fi
    echo "SETUP: $done_what; $setup_what; build OK"
    exit 0
  fi
  v=$(newer "$(cache_best)" "$MAPPERLY_DEFAULT")
  done_what=""
  if grep -qi 'Include="Riok.Mapperly"' "$csproj"; then
    done_what="Riok.Mapperly already in $csproj"
  else
    add_package Riok.Mapperly "$v" ' ExcludeAssets="runtime" PrivateAssets="all"'
    done_what="Riok.Mapperly $v added to $csproj${props:+ (its version in $props)}, compile time only (ExcludeAssets runtime, PrivateAssets all)"
  fi
  # C# 9 at least: the default of a netstandard, .NET Framework or .NET Core 3 target is older
  lang=""
  tfms=$(sed -n -E 's/.*<TargetFrameworks?>([^<]*)<.*/\1/p' "$csproj" | tr ';' '\n' | grep .)
  if [ -n "$tfms" ] && printf '%s\n' "$tfms" | grep -q -v -E '^net([5-9]|[1-9][0-9])\.[0-9]' &&
    ! { cat "$csproj"; props_above "$project" Build | xargs cat 2>/dev/null; } | grep -q '<LangVersion>'; then
    awk '!done && /<\/PropertyGroup>/ { print "    <LangVersion>latest</LangVersion>"; done = 1 } { print }' "$csproj" > "$tmp/csproj.new" && cat "$tmp/csproj.new" > "$csproj"
    lang="; LangVersion latest (Mapperly needs C# 9, the default of $(printf '%s\n' "$tfms" | grep -v -E '^net([5-9]|[1-9][0-9])\.[0-9]' | head -n 1) is older)"
  fi
  if ! grep -q 'Mapperly.globalconfig' "$csproj"; then
    awk '
      !done && /<\/Project>/ {
        print "  <ItemGroup>"
        print "    <!-- Mapperly: a mapping left incomplete or ambiguous fails the build (automapper.sh setup) -->"
        print "    <GlobalAnalyzerConfigFiles Include=\"Mapperly.globalconfig\" />"
        print "  </ItemGroup>"
        print ""
        done = 1
      }
      { print }' "$csproj" > "$tmp/csproj.new" && cat "$tmp/csproj.new" > "$csproj"
  fi
  if [ ! -f "$config" ]; then
    {
      echo "is_global = true"
      echo ""
      echo "# Mapperly (written by automapper.sh setup; the application owns it): what would map wrong or not at all fails the"
      echo "# build, as AssertConfigurationIsValid of AutoMapper did at run time"
      for id in $STRICT; do
        case "$id" in
          RMG003) why="no member of the two enums matches" ;;
          RMG004) why="an ignored target member that does not exist" ;;
          RMG012) why="a target member without source: map it or ignore it by name" ;;
          RMG020) why="a source member left out, in a method that asks for every one ([MapperRequiredMapping(Source)])" ;;
          RMG021) why="an ignored source member that does not exist" ;;
          RMG037) why="a target enum member without source member, when the method asks for it" ;;
          RMG038) why="a source enum member without target member: it would throw at run time" ;;
          RMG049) why="a source member ignored and mapped" ;;
          RMG050) why="a target member ignored and mapped" ;;
          RMG060) why="two user methods for the same types, none of them [UserMapping(Default = true)]" ;;
          RMG066) why="an object mapping that maps no member" ;;
          RMG068) why="a helper of a projection that cannot be inlined: the query would load whole rows" ;;
          RMG072) why="the method of a Use does not take the type of the source" ;;
          RMG073) why="the method of a Use does not give the type of the target" ;;
        esac
        echo "# $why"
        echo "dotnet_diagnostic.$id.severity = error"
      done
    } > "$config"
    wrote="$wrote $config"
  fi
  if [ ! -f "$project/MapperDefaults.cs" ]; then
    cat > "$project/MapperDefaults.cs" <<'EOF'
using Riok.Mapperly.Abstractions;

// The rules of every Mapperly mapper of this project, as AutoMapper mapped (written by automapper.sh setup; the
// application owns it): every target member has its source or is ignored by name (Mapperly.globalconfig makes it an
// error); a source enum member without target member is an error too (it would throw); helper methods only where a
// mapping names them (Use = nameof(...)), or for every pair of their types when marked [UserMapping(Default = true)];
// enums by name, case ignored; member names compared without case.
[assembly: MapperDefaults(
    RequiredMappingStrategy = RequiredMappingStrategy.Target,
    RequiredEnumMappingStrategy = RequiredMappingStrategy.Source,
    AutoUserMappings = false,
    EnumMappingStrategy = EnumMappingStrategy.ByName,
    EnumMappingIgnoreCase = true,
    PropertyNameMappingStrategy = PropertyNameMappingStrategy.CaseInsensitive)]
EOF
    wrote="$wrote $project/MapperDefaults.cs"
  fi
  out=$(sh "$here/build-test.sh" --build-only "$csproj" 2>&1)
  if ! printf '%s\n' "$out" | grep -q '^BUILD: OK'; then
    undo
    printf '%s\n' "$out" | tail -n 15
    echo "STOP: the build of $csproj fails with Riok.Mapperly $v: every file put back, nothing changed"
    exit 1
  fi
  echo "SETUP: $done_what$lang; $config (the diagnostics of a mapping left incomplete or ambiguous as errors) and $project/MapperDefaults.cs (the rules of its mappers, as AutoMapper mapped)$([ -z "$wrote" ] && echo ", kept as they were"); build OK"
  exit 0
fi

# ---------- scaffold ----------
# the translator of the maps of a profile and the table of the types of the members, written for the call
write_awk() {
  cat > "$tmp/props.awk" <<'AWK'
# "<type>\t<member>\t<its type>" for each property and each parameter of a primary constructor of the C# files given
FNR == 1 { cls = "" }
{
  line = $0
  sub(/\/\/.*$/, "", line)
  if (match(line, /(record[ \t]+struct|record[ \t]+class|class|record|struct|interface)[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
    t = substr(line, RSTART, RLENGTH); sub(/^(record[ \t]+struct|record[ \t]+class|class|record|struct|interface)[ \t]+/, "", t)
    pre = substr(line, 1, RSTART - 1)
    if (pre !~ /[=(.]/) {
      cls = t
      rest = substr(line, RSTART + RLENGTH)
      if (rest ~ /^[ \t]*(<[^>]*>)?[ \t]*\(/) {
        p = rest; sub(/^[^(]*\(/, "", p); sub(/\)[^)]*$/, "", p)
        n = split(p, a, ",")
        for (k = 1; k <= n; k++) {
          x = a[k]; gsub(/^[ \t]+|[ \t]+$/, "", x); sub(/[ \t]*=.*$/, "", x)
          m = x; sub(/^.*[ \t]/, "", m); ty = x; sub(/[ \t]+[A-Za-z_][A-Za-z0-9_]*$/, "", ty)
          if (m ~ /^[A-Za-z_][A-Za-z0-9_]*$/ && ty != "" && ty != m) print cls "\t" m "\t" ty
        }
      }
      next
    }
  }
  if (cls == "") next
  if (line ~ /^[ \t]*public[ \t]/ && line ~ /\{[ \t]*(get|set|init|private|protected|internal)|=>/ && line !~ /\(/) {
    x = line; sub(/^[ \t]*public[ \t]+/, "", x)
    while (x ~ /^(virtual|override|new|required|static|abstract|sealed|readonly|partial)[ \t]/) sub(/^[A-Za-z]+[ \t]+/, "", x)
    sub(/[ \t]*(\{|=>).*$/, "", x)
    m = x; sub(/^.*[ \t]/, "", m); ty = x; sub(/[ \t]+[A-Za-z_][A-Za-z0-9_]*$/, "", ty)
    if (m ~ /^[A-Za-z_][A-Za-z0-9_]*$/ && ty != "" && ty != m) print cls "\t" m "\t" ty
  }
}
AWK
  cat > "$tmp/translate.awk" <<'AWK'
# The maps of an AutoMapper profile translated for Mapster (mode=mapster: the body of an IRegister) or for Mapperly
# (mode=mapperly: the members of a mapper class). Input: the statements of the profile, "<first>\t<last>\t<text>" (each
# CreateMap on one line), then the profile itself (its lines, quoted for a map left to finish). Variables: mode,
# static ("static " or ""), this ("this " or ""), props (a file of "<type>\t<member>\t<its type>" lines: the type of a
# helper). Portable awk (mawk, gawk, BWK, busybox): no gensub, no arrays of arrays.
# Output: the code; then the lines "@METHOD <name> <source>" and "@TODO <n>" for the shell.
BEGIN {
  FS = "\t"
  if (props != "") {
    while ((getline line < props) > 0) {
      split(line, p, "\t")
      if (!((p[1] SUBSEP p[2]) in ptype)) { ptype[p[1], p[2]] = p[3]; pmem[p[1]] = pmem[p[1]] " " p[2] }
    }
    close(props)
  }
  ind = "        "
  todos = 0
}
FNR == NR { st[++ns] = $0; next }
{ src[FNR] = $0 }
END {
  for (stk = 1; stk <= ns; stk++) {
    split(st[stk], f, "\t")
    translate(f[1] + 0, f[2] + 0, f[3])
  }
  if (mode == "mapperly" && helpers != "") printf "%s", helpers
  print "@TODO " todos
}

# ---------- text helpers ----------
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function simple(t) { sub(/<.*/, "", t); sub(/.*\./, "", t); sub(/\?$/, "", t); return t }
function skip_str(s, i,   n, c, q) {
  n = length(s); q = substr(s, i, 1); i++
  while (i <= n) { c = substr(s, i, 1); if (c == "\\" && q != "@") { i += 2; continue } if (c == q) return i + 1; i++ }
  return i
}
# the index of the bracket that closes the one at i ( ( { [ ), strings skipped; 0 when none
function close_of(s, i,   n, d, c) {
  n = length(s); d = 0
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\"" || c == "'") { i = skip_str(s, i); continue }
    if (c == "(" || c == "{" || c == "[") d++
    else if (c == ")" || c == "}" || c == "]") { d--; if (d == 0) return i }
    i++
  }
  return 0
}
# the > that closes a generic list at i (<), 0 when what follows is no list of types (a comparison)
function angle_of(s, i,   n, d, c) {
  n = length(s); d = 0
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "<") d++
    else if (c == ">") { d--; if (d == 0) return i }
    else if (c !~ /[A-Za-z0-9_., ?\[\]]/) return 0
    i++
  }
  return 0
}
# the parts of s split at its top-level commas: np, part[1..np]
function split_top(s,   n, i, c, d, st, j) {
  np = 0; n = length(s); d = 0; st = 1; i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\"" || c == "'") { i = skip_str(s, i); continue }
    if (c == "<" && i > 1 && substr(s, i - 1, 1) ~ /[A-Za-z0-9_]/) { j = angle_of(s, i); if (j) { i = j + 1; continue } }
    if (c == "(" || c == "{" || c == "[") d++
    else if (c == ")" || c == "}" || c == "]") d--
    else if (c == "," && d == 0) { part[++np] = trim(substr(s, st, i - st)); st = i + 1 }
    i++
  }
  part[++np] = trim(substr(s, st))
}
# a chain of calls: "Name<gen>(args).Name2(args)…" -> cn, cname[], cgen[], cargs[]; 0 when s is something else
function chain(s,   n, i, j, name, gen) {
  cn = 0; n = length(s); i = 1
  while (i <= n) {
    while (i <= n && substr(s, i, 1) ~ /[ \t.]/) i++
    if (i > n) break
    j = i
    while (j <= n && substr(s, j, 1) ~ /[A-Za-z0-9_]/) j++
    if (j == i) return 0
    name = substr(s, i, j - i); i = j
    while (i <= n && substr(s, i, 1) == " ") i++
    gen = ""
    if (substr(s, i, 1) == "<") { j = angle_of(s, i); if (!j) return 0; gen = substr(s, i + 1, j - i - 1); i = j + 1 }
    while (i <= n && substr(s, i, 1) == " ") i++
    if (substr(s, i, 1) != "(") return 0
    j = close_of(s, i)
    if (!j) return 0
    cn++; cname[cn] = name; cgen[cn] = trim(gen); cargs[cn] = trim(substr(s, i + 1, j - i - 1))
    i = j + 1
  }
  return cn
}
# a lambda "p => body" or "(a, b) => body": lp (its parameter names, comma separated), lpn (their count), lb (its body)
function lambda(s,   n, i, c, d, ps, k, a, x) {
  lp = ""; lpn = 0; lb = ""
  s = trim(s); n = length(s); d = 0
  for (i = 1; i < n; i++) {
    c = substr(s, i, 1)
    if (c == "\"" || c == "'") { i = skip_str(s, i) - 1; continue }
    if (c == "(") d++
    else if (c == ")") d--
    else if (d == 0 && substr(s, i, 2) == "=>") break
  }
  if (i >= n) return 0
  ps = trim(substr(s, 1, i - 1)); lb = trim(substr(s, i + 2))
  sub(/^static[ \t]+/, "", ps)
  if (ps ~ /^\(/) { ps = substr(ps, 2, length(ps) - 2) }
  k = split(ps, a, ",")
  for (i = 1; i <= k; i++) { x = trim(a[i]); sub(/.*[ \t]/, "", x); lp = lp (lpn ? "," : "") x; lpn++ }
  return 1
}
function lparam(k,   a) { split(lp, a, ","); return a[k] }
# the code of s: its strings taken out, the holes {…} of an interpolated string kept
function code_only(s,   n, i, c, out, interp, d, q) {
  n = length(s); out = ""; i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "'") { i = skip_str(s, i); out = out "''"; continue }
    if (c == "\"") {
      interp = (i > 1 && substr(s, i - 1, 1) == "$") || (i > 2 && substr(s, i - 2, 2) == "$@")
      i++
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\") { i += 2; continue }
        if (c == "\"") { i++; break }
        if (interp && c == "{") {
          if (substr(s, i + 1, 1) == "{") { i += 2; continue }
          d = 1; i++
          while (i <= n && d > 0) { c = substr(s, i, 1); if (c == "{") d++; else if (c == "}") d--; if (d > 0) out = out c; i++ }
          out = out " "
          continue
        }
        i++
      }
      out = out "\"\""
      continue
    }
    out = out c; i++
  }
  return out
}
# whether the word w is used in the code of s
function uses(s, w,   i, n, b, a) {
  s = code_only(s)
  n = length(w)
  while ((i = index(s, w)) > 0) {
    b = i > 1 ? substr(s, i - 1, 1) : " "; a = substr(s, i + n, 1)
    if (b !~ /[A-Za-z0-9_.]/ && a !~ /[A-Za-z0-9_]/) return 1
    s = substr(s, i + n)
  }
  return 0
}
# the member path of a body "p.A.B" for the parameter p, "" when the body is anything else
function path_of(body, p) {
  if (body !~ /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$/) return ""
  if (substr(body, 1, length(p) + 1) != p ".") return ""
  return substr(body, length(p) + 2)
}
# the type of a member, from the declarations of the repository ("" when unknown)
function type_of(t, m) { t = simple(t); return ((t SUBSEP m) in ptype) ? ptype[t, m] : "" }
function uniq(name, other,   k) {
  k = name
  if ((k in used) && other != "") k = other
  while (k in used) k = k "2"
  used[k] = 1
  return k
}
function todo(text) { todos++; nt++; tlist[nt] = text }

# ---------- one map ----------
function translate(first, last, text,   s, d, hdr, args, i, k, name, rev, sp, dp) {
  nt = 0; nl = 0; nb = 0; na = 0; nc = 0; nattr = 0; nrattr = 0; wrap = 0; sourcelist = 0; reverse = 0; nfwd = 0
  # CreateMap<S, D>(…) or CreateMap(typeof(S), typeof(D))
  if (!chain(text) || cname[1] != "CreateMap") { quote(first, last, "a form the script does not read"); todos++; return }
  if (cgen[1] != "") { split_top(cgen[1]); s = part[1]; d = part[2] }
  else { split_top(cargs[1]); s = part[1]; d = part[2]; gsub(/^typeof\(|\)$/, "", s); gsub(/^typeof\(|\)$/, "", d) }
  if (cargs[1] ~ /MemberList\.(Source|None)/) sourcelist = cargs[1] ~ /Source/ ? 1 : 2
  if (s ~ /<>/ || d ~ /<>/) {
    quote(first, last, "")
    if (mode == "mapster") { print ind "config.NewConfig(typeof(" s "), typeof(" d "));"; print "" }
    else { todos++; print "    // TODO: an open generic: a generic method written by hand (the skill automapper)"; print "" }
    return
  }
  S = s; D = d
  # the calls after CreateMap, in order; those after ReverseMap belong to the way back
  ncall = cn
  for (i = 2; i <= ncall; i++) { kn[i] = cname[i]; kg[i] = cgen[i]; ka[i] = cargs[i] }
  if (mode == "mapster") mapster_map(first, last)
  else mapperly_map(first, last)
}

# ---------- Mapster ----------
function mapster_map(first, last,   i, k, out, n, back, line) {
  n = 0; back = 0
  out[++n] = ind "config.NewConfig<" S ", " D ">()"
  if (sourcelist) out[++n] = ind "    .RequireDestinationMemberSource(false)"
  for (i = 2; i <= ncall; i++) {
    if (kn[i] == "ReverseMap") {
      out[++n] = ind "    ;"
      back = 1
      out[++n] = ""
      out[++n] = ind "config.NewConfig<" D ", " S ">()"
      out[++n] = ind "    .Unflattening(true)"
      out[++n] = ind "    .RequireDestinationMemberSource(false)"
      for (k = 1; k <= nfwd; k++) out[++n] = ind "    .Map(r => r." fwdto[k] ", s => s." fwdfrom[k] ")"
      continue
    }
    line = mapster_call(kn[i], kg[i], ka[i], back)
    if (line != "") out[++n] = ind "    " line
  }
  if (nt) quote(first, last, "to finish: its TODO lines")
  for (i = 1; i <= n; i++) print out[i]
  print ind "    ;"
  print ""
}
# one call of the chain, as Mapster writes it ("" when it has no line)
function mapster_call(name, gen, args, back,   o, i, k, dl, dpath, r, v, cond) {
  if (name == "ForMember" || name == "ForPath") {
    split_top(args)
    dl = part[1]; o = part[2]
    if (!lambda(dl)) return todo_line(name, gen, args)
    dpath = path_of(lb, lparam(1))
    if (dpath == "") return todo_line(name, gen, args)
    if (!options(o)) return todo_line(name, gen, args)
    if (oignore) return ".Ignore(" dl ")"
    if (ores != "" || ouse) return todo_line(name, gen, args)
    v = ""
    if (ofrom != "") {
      if (ofrom ~ /^"/) { r = ofrom; gsub(/"/, "", r); v = "s => s." r }
      else {
        if (!lambda(ofrom)) return todo_line(name, gen, args)
        if (lpn == 2 && !uses(lb, lparam(2))) v = lparam(1) " => " lb
        else if (lpn == 1) v = ofrom
        else return todo_line(name, gen, args)
        if (!back && lpn >= 1 && path_of(lb, lparam(1)) != "" && dpath !~ /\./) { nfwd++; fwdto[nfwd] = path_of(lb, lparam(1)); fwdfrom[nfwd] = dpath }
      }
    }
    if (onull != "") {
      # the member of the same name in the source (a flattened one has no path to put ?? after)
      if (v == "" && dpath !~ /\./ && type_of(S, dpath) == "") return todo_line(name, gen, args)
      if (v == "") v = "s => s." dpath " ?? " onull
      else { lambda(v); v = lparam(1) " => (" lb ") ?? " onull }
    }
    if (ocond != "") {
      # Condition of AutoMapper: the member left as it is when false (IgnoreIf); the third argument of Map would set
      # it to its default value
      if (!lambda(ocond) || lpn > 2 || lb ~ /^\{/) return todo_line(name, gen, args)
      cond = ".IgnoreIf((" lparam(1) ", " (lpn == 2 ? lparam(2) : "_") ") => !(" lb "), " dl ")"
    }
    if (v == "") return cond != "" ? cond : todo_line(name, gen, args)
    return ".Map(" dl ", " v ")" cond
  }
  if (name == "ForCtorParam") {
    split_top(args)
    if (!options(part[2]) || ofrom == "" || ofrom ~ /^"/ || ocond != "" || onull != "" || oignore) return todo_line(name, gen, args)
    return ".Map(" part[1] ", " ofrom ")"
  }
  if (name == "BeforeMap" || name == "AfterMap") {
    if (gen != "" || !lambda(args)) return todo_line(name, gen, args)
    if (lpn == 3 && uses(lb, lparam(3))) return todo_line(name, gen, args)
    return "." (name == "BeforeMap" ? "BeforeMapping" : "AfterMapping") "((" lparam(1) ", " lparam(2) ") => " lb ")"
  }
  if (name == "ConvertUsing" || name == "ConstructUsing") {
    if (gen != "" || !lambda(args)) return todo_line(name, gen, args)
    if (lpn > 1) { for (i = 2; i <= lpn; i++) if (uses(lb, lparam(i))) return todo_line(name, gen, args) }
    return "." (name == "ConvertUsing" ? "MapWith" : "ConstructUsing") "(" lparam(1) " => " lb ")"
  }
  if (name == "Include") return ".Include<" gen ">()"
  if (name == "IncludeBase") return ".Inherits<" gen ">()"
  if (name == "MaxDepth") return ".MaxDepth(" args ")"
  if (name == "PreserveReferences") return ".PreserveReference(true)"
  if (name == "ValidateMemberList") return args ~ /MemberList\.(Source|None)/ ? ".RequireDestinationMemberSource(false)" : ""
  if (name == "DisableCtorValidation" || name == "ForSourceMember") return ""
  if (name == "ForAllMembers" && nullcheck(args)) return ".IgnoreNullValues(true)"
  if (name == "AddTransform" && gen != "" && lambda(args) && lpn == 1) return ".AddDestinationTransform((" gen " " lparam(1) ") => " lb ")"
  return todo_line(name, gen, args)
}
function todo_line(name, gen, args) {
  todo(name)
  return "// TODO: ." name (gen != "" ? "<" gen ">" : "") "(" args "): by hand (the skill mapster)"
}
# ForAllMembers(o => o.Condition((s, d, m) => m != null)): the null values not mapped
function nullcheck(args,   o, inner) {
  if (!lambda(args)) return 0
  o = lparam(1); inner = lb
  if (!chain(substr(inner, length(o) + 2)) || cn != 1 || cname[1] != "Condition") return 0
  if (!lambda(cargs[1]) || lpn < 3) return 0
  return lb == lparam(3) " != null" || lb == lparam(3) " is not null"
}
# the options of a member: o => o.MapFrom(…), o => { o.MapFrom(…); o.Condition(…); } -> ofrom, ocond, onull, oignore,
# ores (a resolver class), ouse (UseDestinationValue); 0 when the lambda holds something else
function options(o,   p, body, stmts, k, a, i, j, x) {
  ofrom = ""; ocond = ""; onull = ""; oignore = 0; ores = ""; ouse = 0
  if (!lambda(o) || lpn != 1) return 0
  p = lparam(1); body = lb
  if (body ~ /^\{/) { body = substr(body, 2, length(body) - 2) }
  gsub(/;[ \t]*$/, "", body)
  k = split_semis(body, a)
  for (i = 1; i <= k; i++) {
    x = trim(a[i])
    if (x == "") continue
    if (substr(x, 1, length(p) + 1) != p ".") return 0
    if (!chain(substr(x, length(p) + 2))) return 0
    for (j = 1; j <= cn; j++) {
      if (cname[j] == "MapFrom") { if (cgen[j] != "") ores = cgen[j]; else ofrom = cargs[j] }
      else if (cname[j] == "Ignore") oignore = 1
      else if (cname[j] == "Condition" || cname[j] == "PreCondition") ocond = cargs[j]
      else if (cname[j] == "NullSubstitute") onull = cargs[j]
      else if (cname[j] == "UseDestinationValue") ouse = 1
      else return 0
    }
  }
  return 1
}
function split_semis(s, a,   n, i, c, d, st, k) {
  k = 0; n = length(s); d = 0; st = 1
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\"" || c == "'") { i = skip_str(s, i) - 1; continue }
    if (c == "(" || c == "{" || c == "[") d++
    else if (c == ")" || c == "}" || c == "]") d--
    else if (c == ";" && d == 0) { a[++k] = substr(s, st, i - st); st = i + 1 }
  }
  a[++k] = substr(s, st)
  return k
}

# ---------- Mapperly ----------
function mapperly_map(first, last,   i, name, gen, args, back, m, w, partialname, k, sname, dname) {
  back = 0
  if (sourcelist == 1) add_attr("[MapperRequiredMapping(RequiredMappingStrategy.Source)]")
  if (sourcelist == 2) add_attr("[MapperRequiredMapping(RequiredMappingStrategy.None)]")
  sname = simple(S); dname = simple(D)
  for (i = 2; i <= ncall; i++) {
    name = kn[i]; gen = kg[i]; args = ka[i]
    if (name == "ReverseMap") { back = 1; reverse = 1; continue }
    if (back) { mapperly_back(name, gen, args); continue }
    mapperly_call(name, gen, args)
  }
  if (convert == "" && !allownull) empty_lists()
  # a destination named by a keyword (string, int…): <Source>To<Type>
  if (dname ~ /^[a-z]/) dname = sname "To" toupper(substr(dname, 1, 1)) substr(dname, 2)
  else dname = "To" dname
  if (wrap && index(" " projected " ", " " simple(D) " "))
    todo("ProjectTo<" simple(D) "> of a map with code around its method (BeforeMap, AfterMap, Condition): that code cannot run in a query; a private partial " simple(D) " method for the query, with the attributes of this map (the skill automapper)")
  if (nt) quote(first, last, "to finish: its TODO lines")
  for (k = 1; k <= nt; k++) print "    // TODO: " tlist[k]
  if (convert != "") { print convert; print "@METHOD " convertname " " S; convert = ""; print ""; return }
  if (wrap) {
    m = uniq(dname)
    partialname = uniq("Map" sname dname)
    print "    [UserMapping(Default = true)]"
    print "    public " static D " " m "(" this S " source)"
    print "    {"
    print "        var target = new " D "();"
    for (k = 1; k <= nb; k++) print "        " blocks_before[k]
    print "        " partialname "(source, target);"
    for (k = 1; k <= nc; k++) print "        " blocks_cond[k]
    for (k = 1; k <= na; k++) print "        " blocks_after[k]
    print "        return target;"
    print "    }"
    print ""
    for (k = 1; k <= nattr; k++) print "    " attr[k]
    print "    private " static "partial void " partialname "(" S " source, " D " target);"
    print "@METHOD " m " " S
  } else {
    m = uniq(dname)
    for (k = 1; k <= nattr; k++) print "    " attr[k]
    print "    public " static "partial " D " " m "(" this S " source);"
    print "@METHOD " m " " S
  }
  if (index(" " projected " ", " " simple(D) " ")) {
    print ""
    print "    // ProjectTo<" simple(D) ">: the query itself (only the columns of " simple(D) " read), with the configuration above"
    if (wrap) print "    // (BeforeMap, AfterMap and conditions run on objects only, never in a query, as with AutoMapper)"
    m = uniq("ProjectTo" simple(D))
    print "    public " static "partial IQueryable<" D "> " m "(this IQueryable<" S "> source);"
    print "@METHOD " m " IQueryable<" S ">"
  }
  if (sourcelist == 1) {
    print ""
    print "    // used onto an existing object, Map(source, destination): every member of the source mapped, the others kept"
    if (wrap) {
      # the same code around the generated method, onto the object given
      print "    public " static "void ApplyTo(" this S " source, " D " target)"
      print "    {"
      for (k = 1; k <= nb; k++) print "        " blocks_before[k]
      print "        " partialname "(source, target);"
      for (k = 1; k <= nc; k++) print "        " blocks_cond[k]
      for (k = 1; k <= na; k++) print "        " blocks_after[k]
      print "    }"
    } else {
      print "    [MapperRequiredMapping(RequiredMappingStrategy.Source)]"
      for (k = 1; k <= nattr; k++) if (attr[k] !~ /^\[MapperRequiredMapping/) print "    " attr[k]
      print "    public " static "partial void ApplyTo(" this S " source, [MappingTarget] " D " target);"
    }
    print "@METHOD ApplyTo " S
  }
  if (reverse) {
    print ""
    m = uniq("To" sname)
    print "    // the way back of ReverseMap"
    for (k = 1; k <= nfwd; k++) print "    [MapProperty(nameof(" D "." fwdfrom[k] "), \"" fwdto[k] "\")]"
    unflatten()
    for (k = 1; k <= nrattr; k++) print "    " rattr[k]
    print "    public " static "partial " S " " m "(" this D " source);"
    print "@METHOD " m " " D
  }
  print ""
}
function add_attr(a) { attr[++nattr] = a }
# each list of D whose source in S may be null: an empty list then, as AutoMapper gave
function empty_lists(   n, a, i, m, dt, st, k, named, hname, inner, conc) {
  n = split(pmem[simple(D)], a, " ")
  for (i = 1; i <= n; i++) {
    m = a[i]; dt = ptype[simple(D), m]; st = ptype[simple(S), m]
    if (st == "" || st !~ /\?$/ || dt ~ /\?$/) continue
    if (dt !~ /^(List|IList|ICollection|IEnumerable|IReadOnlyList|IReadOnlyCollection|HashSet|ISet|Collection)<.*>$/ && dt !~ /\[\]$/) continue
    named = 0
    for (k = 1; k <= nattr; k++) if (index(attr[k], "nameof(" D "." m ")") || index(attr[k], "nameof(" S "." m ")")) named = 1
    if (named) continue
    hname = uniq(m "OrEmpty", simple(D) m "OrEmpty")
    inner = uniq("Map" m, "Map" simple(D) m)
    conc = dt ~ /^(List|HashSet|Collection)</ ? "new " dt "()" : "[]"
    add_attr("[MapProperty(nameof(" S "." m "), nameof(" D "." m "), Use = nameof(" hname "))]")
    helpers = helpers "    // a null list gives an empty one, as AutoMapper did\n"
    helpers = helpers "    private " static dt " " hname "(" st " value) => value == null ? " conc " : " inner "(value);\n\n"
    st2 = st; sub(/\?$/, "", st2)
    helpers = helpers "    private " static "partial " dt " " inner "(" st2 " value);\n\n"
  }
}
# the members of D named after a member of S and one of its own (AddressCity: Address.City), mapped back
function unflatten(   sm, n, a, i, t, dm, nd, b, j, rest, k, done) {
  n = split(pmem[simple(S)], a, " ")
  nd = split(pmem[simple(D)], b, " ")
  for (i = 1; i <= n; i++) {
    t = ptype[simple(S), a[i]]; sub(/\?$/, "", t)
    if (pmem[simple(t)] == "") continue
    for (j = 1; j <= nd; j++) {
      if (b[j] == a[i] || substr(b[j], 1, length(a[i])) != a[i]) continue
      rest = substr(b[j], length(a[i]) + 1)
      if (!((simple(t) SUBSEP rest) in ptype)) continue
      done = 0
      for (k = 1; k <= nfwd; k++) if (fwdfrom[k] == b[j]) done = 1
      if (!done) print "    [MapProperty(nameof(" D "." b[j] "), \"" a[i] "." rest "\")]"
    }
  }
}
function helper(type, hname, params, body) {
  if (type == "") { todo("the type of " hname ": not found in the declarations, object until then"); type = "object /* TODO: its type */" }
  helpers = helpers "    private " static type " " hname "(" params ") => " body ";\n\n"
}
# an alias of the source and the target for the body of a lambda: { var s = source; … }
function aliased(body, ps, ts,   pre) {
  pre = ""
  if (ps != "" && ps != "source" && uses(body, ps)) pre = pre "var " ps " = source; "
  if (ts != "" && ts != "target" && uses(body, ts)) pre = pre "var " ts " = target; "
  if (body ~ /^\{/) body = trim(substr(body, 2, length(body) - 2))
  else body = body ";"
  return "{ " pre body " }"
}
function mapperly_call(name, gen, args,   o, dl, dpath, v, hname, t, ts, member, p, target, ps, i, c) {
  if (name == "ForMember" || name == "ForPath" || name == "ForCtorParam") {
    split_top(args)
    dl = part[1]; o = part[2]
    if (name == "ForCtorParam") { member = dl; gsub(/"/, "", member); if (member ~ /^nameof\(/) { sub(/^nameof\([^.]*\./, "", member); sub(/\)$/, "", member) } dpath = member }
    else {
      if (!lambda(dl)) return todo(name ": " args)
      dpath = path_of(lb, lparam(1))
      if (dpath == "") return todo(name ": " args)
    }
    if (!options(o)) return todo(name ": " args)
    if (ores != "") return todo(name " " dpath ": the resolver " ores " (its code in a method of the mapper; its services in the constructor of the mapper)")
    if (ouse) return todo(name " " dpath ": UseDestinationValue ([MapperIgnoreTarget] on the void method)")
    if (oignore) { if (dpath ~ /\./) return todo(name ": " args); add_attr("[MapperIgnoreTarget(nameof(" D "." dpath "))]"); return }
    target = dpath ~ /\./ || name == "ForCtorParam" ? "\"" dpath "\"" : "nameof(" D "." dpath ")"
    # the value: a path, the source itself, or code in a helper
    if (ofrom ~ /^"/) { v = ofrom; gsub(/"/, "", v); ofrom = "s => s." v }
    if (ofrom != "") {
      if (!lambda(ofrom)) return todo(name ": " args)
      if (lpn == 2 && !uses(lb, lparam(2))) lpn = 1
      if (lpn != 1) return todo(name ": " args)
      p = lparam(1)
    }
    if (ocond != "") {
      # a condition: in the method around the generated one, the member left alone by the generated one
      if (dpath ~ /\./) return todo(name ": " args)
      wrap = 1
      add_attr("[MapperIgnoreTarget(nameof(" D "." dpath "))]")
      if (ofrom != "") { lambda(ofrom); v = lb; ps = lparam(1) } else { v = "source." dpath; ps = "" }
      # every source member mapped (MemberList.Source): the one the condition maps is left to the method around
      if (sourcelist == 1) {
        t = ofrom == "" ? dpath : path_of(v, ps)
        if (t != "" && t !~ /\./) add_attr("[MapperIgnoreSource(nameof(" S "." t "))]")
      }
      if (onull != "") v = "(" v ") ?? " onull
      lambda(ocond)
      if (lpn != 1) return todo(name ": " args)
      c = aliased("{ if (" lb ") { target." dpath " = " v "; } }", lparam(1), "")
      if (ps != "" && ps != lparam(1) && ps != "source" && uses(v, ps)) c = "{ var " ps " = source; " substr(c, 3)
      blocks_cond[++nc] = c
      return
    }
    if (ofrom != "") {
      lambda(ofrom); p = lparam(1)
      if (lb == p) { add_attr("[MapPropertyFromSource(" target ")]"); return }
      v = path_of(lb, p)
      if (v != "" && onull == "") {
        if (v ~ /\./) add_attr("[MapProperty(\"" v "\", " target ")]")
        else add_attr("[MapProperty(nameof(" S "." v "), " target ")]")
        if (dpath !~ /\./ && name != "ForCtorParam") { nfwd++; fwdto[nfwd] = v; fwdfrom[nfwd] = dpath }
        return
      }
      hname = uniq(dpath ~ /\./ ? "Value" : dpath, simple(D) dpath)
      t = type_of(D, dpath)
      add_attr("[MapPropertyFromSource(" target ", Use = nameof(" hname "))]")
      helper(t, hname, S " " p, onull != "" ? "(" lb ") ?? " onull : lb)
      return
    }
    if (onull != "") {
      hname = uniq(dpath "OrDefault", simple(D) dpath "OrDefault")
      t = type_of(D, dpath); ts = type_of(S, dpath)
      if (ts == "") ts = t
      if (ts == "") ts = "object /* TODO: its type */"
      else if (ts !~ /\?$/) ts = ts "?"
      add_attr("[MapProperty(nameof(" S "." dpath "), " target ", Use = nameof(" hname "))]")
      helper(t, hname, ts " value", "value ?? " onull)
      return
    }
    return todo(name ": " args)
  }
  if (name == "BeforeMap" || name == "AfterMap") {
    if (gen != "" || !lambda(args) || lpn < 2 || (lpn == 3 && uses(lb, lparam(3)))) return todo(name ": " args)
    wrap = 1
    if (name == "BeforeMap") blocks_before[++nb] = aliased(lb, lparam(1), lparam(2))
    else blocks_after[++na] = aliased(lb, lparam(1), lparam(2))
    return
  }
  if (name == "ConvertUsing") {
    if (gen != "") return todo("ConvertUsing<" gen ">: the code of its Convert in a [UserMapping(Default = true)] method of the mapper, " simple(S) " to " simple(D))
    if (!lambda(args)) return todo(name ": " args)
    if (lpn > 1) { for (i = 2; i <= lpn; i++) if (uses(lb, lparam(i))) return todo(name ": " args) }
    hname = uniq(simple(S) "To" (simple(D) ~ /^[a-z]/ ? toupper(substr(simple(D), 1, 1)) substr(simple(D), 2) : simple(D)))
    convert = "    [UserMapping(Default = true)]\n    private " static D " " hname "(" S " " lparam(1) ") => " lb ";"
    convertname = hname
    return
  }
  if (name == "ConstructUsing") {
    if (gen != "" || !lambda(args)) return todo(name ": " args)
    if (lpn > 1) { for (i = 2; i <= lpn; i++) if (uses(lb, lparam(i))) return todo(name ": " args) }
    hname = uniq("Create" simple(D))
    helpers = helpers "    [ObjectFactory]\n    private " static D " " hname "(" S " " lparam(1) ") => " lb ";\n\n"
    return
  }
  if (name == "Include") { add_attr("[MapDerivedType<" gen ">]"); return }
  if (name == "IncludeBase") { split_top(gen); add_attr("[IncludeMappingConfiguration(nameof(To" simple(part[2]) "))]"); return }
  if (name == "ValidateMemberList") {
    if (args ~ /MemberList\.Source/) { sourcelist = 1; add_attr("[MapperRequiredMapping(RequiredMappingStrategy.Source)]") }
    else if (args ~ /MemberList\.None/) add_attr("[MapperRequiredMapping(RequiredMappingStrategy.None)]")
    return
  }
  if (name == "DisableCtorValidation") return
  if (name == "ForSourceMember") return
  if (name == "MaxDepth" || name == "PreserveReferences") return todo(name ": a cycle or a depth, [Mapper(UseReferenceHandling = true)] (the skill automapper)")
  if (name == "ForAllMembers" && nullcheck(args)) return todo("ForAllMembers, null values not mapped: a mapper class of its own, [Mapper(AllowNullPropertyAssignment = false)]")
  return todo(name (gen != "" ? "<" gen ">" : "") ": " args)
}
# the options after ReverseMap, on the way back
function mapperly_back(name, gen, args,   o, dl, dpath, sv, dv, k) {
  reverse = 1
  if (name == "ForMember" || name == "ForPath") {
    split_top(args); dl = part[1]; o = part[2]
    if (!lambda(dl)) return todo("way back, " name ": " args)
    dpath = path_of(lb, lparam(1))
    if (dpath == "" || !options(o)) return todo("way back, " name ": " args)
    if (oignore && dpath !~ /\./) { rattr[++nrattr] = "[MapperIgnoreTarget(nameof(" S "." dpath "))]"; return }
    if (ofrom != "" && lambda(ofrom) && lpn == 1 && path_of(lb, lparam(1)) != "") {
      sv = path_of(lb, lparam(1))
      rattr[++nrattr] = "[MapProperty(\"" sv "\", \"" dpath "\")]"
      return
    }
  }
  todo("way back, " name ": " args)
}
function quote(first, last, why,   i, l) {
  if (why == "") return
  if (mode == "mapster") {
    print ind "// AutoMapper (" why "):"
    for (i = first; i <= last; i++) { l = src[i]; sub(/^[ \t]+/, "", l); print ind "//   " l }
  } else {
    print "    // AutoMapper (" why "):"
    for (i = first; i <= last; i++) { l = src[i]; sub(/^[ \t]+/, "", l); print "    //   " l }
  }
}
AWK
}

if [ "$action" = scaffold ]; then
  target=mapperly
  [ "$1" = --mapster ] && { target=mapster; shift; }
  file=$(from_root "$1")
  [ -n "$file" ] && [ -f "$file" ] || { echo "STOP: automapper.sh scaffold [--mapster] <the .cs file of a profile>"; exit 1; }
  statements "$file" > "$tmp/st"
  [ -s "$tmp/st" ] || { echo "STOP: no CreateMap in $file"; exit 1; }
  profile=$(grep -o -E 'class[[:space:]]+[A-Za-z0-9_]+' "$file" | head -n 1 | sed -E 's/class[[:space:]]+//')
  name=$(printf '%s' "$profile" | sed -E 's/(Mapping)?Profile$//')
  [ -n "$name" ] || name=$profile
  ns=$(sed -n -E 's/^[[:space:]]*namespace[[:space:]]+([A-Za-z0-9_.]+).*/\1/p' "$file" | head -n 1)
  write_awk
  # the types of the members of the repository: the type of a helper method
  cs_files | grep -v -E '(^|/)(bin|obj)/' | tr '\n' '\0' | xargs -0 awk -f "$tmp/props.awk" > "$tmp/props.tsv" 2>/dev/null
  # the destinations of a ProjectTo somewhere in the code: a projection method (Mapperly)
  projected=$(git grep --untracked -h -o -E 'ProjectTo<[A-Za-z0-9_.]+>' -- '*.cs' 2>/dev/null | sed -E 's/ProjectTo<(.*)>/\1/; s/.*\.//' | sort -u | tr '\n' ' ')
  # AllowNullCollections = true somewhere: a null list stays null, as AutoMapper then did
  allownull=0
  git grep --untracked -q -E 'AllowNullCollections[[:space:]]*=[[:space:]]*true' -- '*.cs' 2>/dev/null && allownull=1
  usings() {
    { printf '%s\n' "$@"; grep -E '^[[:space:]]*using[[:space:]]' "$file" | grep -v -E 'AutoMapper' | sed 's/^[[:space:]]*//'; } |
      sort -u | awk '/^using System[.;]/ { print; next } { rest = rest $0 "\n" } END { printf "%s", rest }'
  }
  if [ "$target" = mapster ]; then
    out="$(dirname "$file")/${name}Register.cs"
    out=${out#./}
    echo "SCAFFOLD: $out (${name}Register, namespace ${ns:-global}) from $profile, $(grep -c . "$tmp/st") map(s), for Mapster"
    [ -f "$out" ] && { echo "KEPT: $out (exists: the application owns it)"; exit 0; }
    awk -v mode=mapster -v props="$tmp/props.tsv" -f "$tmp/translate.awk" "$tmp/st" "$file" > "$tmp/body"
    {
      usings "using Mapster;"
      echo ""
      [ -n "$ns" ] && { echo "namespace $ns;"; echo ""; }
      echo "// The maps of $profile for Mapster (written by automapper.sh scaffold --mapster; the application"
      echo "// owns it): each map of AutoMapper translated; a map quoted above its code has TODO lines to finish"
      echo "// (the skill mapster). The rules of every map, as AutoMapper mapped: MapsterSetup.cs."
      echo "public class ${name}Register : IRegister"
      echo "{"
      echo "    public void Register(TypeAdapterConfig config)"
      echo "    {"
      grep -v '^@' "$tmp/body"
      echo "    }"
      echo "}"
    } | awk 'NR > 1 { if (!(prev == "" && ($0 ~ /^ *}$/))) print prev } { prev = $0 } END { print prev }' > "$out"
    todo=$(sed -n 's/^@TODO //p' "$tmp/body")
    echo "WRITTEN: $out"
    echo "NEXT: ${todo:-0} TODO line(s) to finish (the skill mapster), then the adapter of the snapshot tests on Mapster; the callers stay on IMapper until the last step (automapper.sh switch)"
    exit 0
  fi
  # Mapperly: an instance mapper when the resolvers, converters or actions of the profile take services
  cut -f3 "$tmp/st" | grep -o -E '(MapFrom|ConvertUsing|BeforeMap|AfterMap)<[A-Za-z0-9_]+>' | sed -E 's/.*<([A-Za-z0-9_]+)>/\1/' | sort -u > "$tmp/classes"
  : > "$tmp/services"
  while IFS= read -r class; do
    git grep --untracked -h -o -E "(class[[:space:]]+${class}|(public|internal)[[:space:]]+${class})[[:space:]]*\\([^)]+\\)" -- '*.cs' 2>/dev/null |
      head -n 1 | sed -E 's/^[^(]*\(//; s/\)$//' | tr ',' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep . >> "$tmp/services"
  done < "$tmp/classes"
  services=$(awk '!seen[$0]++' "$tmp/services" | paste -s -d, - | sed 's/,/, /g')
  if [ -n "$services" ]; then
    kind="public partial class ${name}Mapper($services)" static="" this=""
  else
    kind="public static partial class ${name}Mapper" static="static " this="this "
  fi
  mapper="$(dirname "$file")/${name}Mapper.cs"
  mapper=${mapper#./}
  echo "SCAFFOLD: $mapper (${name}Mapper, namespace ${ns:-global}) from $profile, $(grep -c . "$tmp/st") map(s)${services:+; an instance mapper: its resolvers take $services}"
  [ -f "$mapper" ] && { echo "KEPT: $mapper (exists: the application owns it)"; exit 0; }
  awk -v mode=mapperly -v static="$static" -v this="$this" -v props="$tmp/props.tsv" -v projected="$projected" -v allownull="$allownull" \
    -f "$tmp/translate.awk" "$tmp/st" "$file" > "$tmp/body"
  {
    linq="" generic=""
    grep -q 'IQueryable<' "$tmp/body" && linq="using System.Linq;"
    grep -q 'List<' "$tmp/body" && generic="using System.Collections.Generic;"
    usings "using Riok.Mapperly.Abstractions;" "$linq" "$generic" | grep .
    echo ""
    [ -n "$ns" ] && { echo "namespace $ns;"; echo ""; }
    echo "// The maps of $profile, generated by Mapperly at build time (written by automapper.sh scaffold; the"
    echo "// application owns it): each map of AutoMapper translated; a map quoted above its method has TODO lines"
    echo "// to finish (the skill automapper). The rules of every mapper of the project: MapperDefaults.cs."
    echo "[Mapper]"
    echo "$kind"
    echo "{"
    grep -v '^@' "$tmp/body"
    echo "}"
  } | awk 'NR > 1 { if (!(prev == "" && $0 == "}")) print prev } { prev = $0 } END { print prev }' > "$mapper"
  todo=$(sed -n 's/^@TODO //p' "$tmp/body")
  echo "WRITTEN: $mapper"
  sed -n 's/^@METHOD /METHOD: /p' "$tmp/body"
  echo "NEXT: ${todo:-0} TODO line(s) to finish (the skill automapper), the build (a target member left without source: error RMG012), then the adapter of the snapshot tests and the callers of these maps${services:+; the mapper registered in place of AddAutoMapper, with the lifetime of its shortest-lived service}"
  exit 0
fi

# ---------- switch (Mapster: the last step) ----------
if [ "$action" = switch ]; then
  folder=$(from_root "$1")
  [ -z "$folder" ] || [ -e "$folder" ] || { echo "STOP: no folder $1"; exit 1; }
  setup_file=$(git grep --untracked -l -E 'static class MapsterSetup' -- '*.cs' 2>/dev/null | head -n 1)
  [ -n "$setup_file" ] || { echo "STOP: no MapsterSetup.cs: automapper.sh setup --mapster <the project of the profiles> first"; exit 1; }
  setupns=$(sed -n -E 's/^[[:space:]]*namespace[[:space:]]+([A-Za-z0-9_.]+).*/\1/p' "$setup_file" | head -n 1)
  # each profile and its Register (written by scaffold --mapster next to it): "OrderProfile=OrderRegister,..."
  registers=$(git grep --untracked -h -o -E 'class[[:space:]]+[A-Za-z0-9_]+[[:space:]]*:[[:space:]]*IRegister' -- '*.cs' 2>/dev/null |
    sed -E 's/class[[:space:]]+([A-Za-z0-9_]+).*/\1/' | sort -u |
    while IFS= read -r r; do
      base=${r%Register}
      git grep --untracked -q -E "class[[:space:]]+${base}(Mapping)?Profile([^A-Za-z0-9_]|\$)" -- '*.cs' 2>/dev/null &&
        git grep --untracked -h -o -E "class[[:space:]]+${base}(Mapping)?Profile([^A-Za-z0-9_]|\$)" -- '*.cs' | head -n 1 | sed -E 's/class[[:space:]]+([A-Za-z0-9_]+).*/\1/' | sed "s/\$/=$r/"
    done | paste -s -d, -)
  cat > "$tmp/switch.awk" <<'AWK'
# automapper.sh switch: one C# file from AutoMapper to Mapster (the last step), what is sure rewritten, the rest left
# as it was (the LEFT lines then, and the build). Variables: setupns (the namespace of MapsterSetup), registers
# ("OrderProfile=OrderRegister,..."). Output: the file, then "@CHANGED <n>" (the count of lines changed).
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
# the index of what closes the bracket at p ("(" or "<"), strings skipped; 0 when the line does not close it
function close_at(s, p,   o, c, d, i, ch) {
  if (substr(s, p, 1) == "(") {
    d = 0; angles = 0
    for (i = p; i <= length(s); i++) {
      ch = substr(s, i, 1)
      if (ch == "\"") { i++; while (i <= length(s) && substr(s, i, 1) != "\"") { if (substr(s, i, 1) == "\\") i++; i++ } continue }
      if (ch == "(") d++
      else if (ch == ")") { d--; if (d == 0) return i }
    }
    return 0
  }
  o = substr(s, p, 1); c = (o == "(" ? ")" : ">"); d = 0
  for (i = p; i <= length(s); i++) {
    ch = substr(s, i, 1)
    if (ch == "\"") { i++; while (i <= length(s) && substr(s, i, 1) != "\"") { if (substr(s, i, 1) == "\\") i++; i++ } continue }
    if (ch == o) d++
    else if (ch == c) { d--; if (d == 0) return i }
  }
  return 0
}
# the change of depth at the character i of s: brackets, and the angles of a generic (List<int>; not => nor a < b)
function depth(s, i,   ch) {
  ch = substr(s, i, 1)
  if (ch == "(" || ch == "{" || ch == "[") return 1
  if (ch == ")" || ch == "}" || ch == "]") return -1
  if (ch == "<" && i > 1 && substr(s, i - 1, 1) ~ /[A-Za-z0-9_]/ && substr(s, i + 1, 1) ~ /[A-Za-z_]/) { angles++; return 1 }
  if (ch == ">" && angles > 0 && substr(s, i - 1, 1) != "=") { angles--; return -1 }
  return 0
}
# the arguments of a call (its text between the parentheses), split at the commas of the top level: their count, in a[]
function split_args(s, a,   n, d, i, ch, cur) {
  n = 0; d = 0; cur = ""; angles = 0
  if (trim(s) == "") return 0
  for (i = 1; i <= length(s); i++) {
    ch = substr(s, i, 1)
    if (ch == "\"") { cur = cur ch; i++; while (i <= length(s) && substr(s, i, 1) != "\"") { if (substr(s, i, 1) == "\\") { cur = cur "\\"; i++ } cur = cur substr(s, i, 1); i++ } cur = cur "\""; continue }
    d += depth(s, i)
    if (ch == "," && d == 0) { a[++n] = trim(cur); cur = ""; continue }
    cur = cur ch
  }
  a[++n] = trim(cur)
  return n
}
# a chain of members and calls (query, _db.Orders, _db.Orders.Where(o => o.Paid)): it takes a call after it as it is
function chain_ok(s,   d, i, ch, e) {
  if (s !~ /^[A-Za-z_@]/) return 0
  d = 0; angles = 0
  for (i = 1; i <= length(s); i++) {
    ch = substr(s, i, 1)
    if (ch == "\"") return 0
    e = depth(s, i)
    if (e != 0) { d += e; continue }
    if (d == 0 && ch !~ /[A-Za-z0-9_.!@]/) return 0
  }
  return d == 0
}
# s with each "from" replaced by "to", where the character before is not one of "before" and the one after not one of
# "after" (regular expressions of one character; "" for any)
function swap(s, from, to, before, after,   r, k, b, c) {
  r = ""
  while ((k = index(s, from)) > 0) {
    b = (k > 1 ? substr(s, k - 1, 1) : ""); c = substr(s, k + length(from), 1)
    if ((before == "" || b == "" || b !~ before) && (after == "" || c == "" || c !~ after)) r = r substr(s, 1, k - 1) to
    else r = r substr(s, 1, k - 1 + length(from))
    s = substr(s, k + length(from))
  }
  return r s
}
# the type that stands for the maps of a profile in AddMapsterMaps: its Register (same namespace), any other type as it
# is (the maps of its assembly); "" for a profile without Register (left by hand)
function marker(t,   simple, pre) {
  t = trim(t); simple = t; pre = ""
  if (match(t, /.*\./)) { pre = substr(t, 1, RLENGTH); simple = substr(t, RLENGTH + 1) }
  if (simple in reg) return pre reg[simple]
  if (simple ~ /Profile$/) return ""
  return t
}
# the types a configuration of AutoMapper names (typeof(X), typeof(X).Assembly, a lambda that only adds profiles or
# maps, or sets the license key): "typeof(A), typeof(B)" (asm: "typeof(A).Assembly, ..."); "" when something else is
# there (left by hand)
function markers(inner, asm,   a, n, k, t, m, out, body, st, ns2, j, s, x, seen) {
  n = split_args(inner, a); out = ""
  for (k = 1; k <= n; k++) {
    t = a[k]
    if (t ~ /^typeof\([^()]+\)(\.(GetTypeInfo\(\)\.)?Assembly)?$/) {
      x = t; sub(/^typeof\(/, "", x); sub(/\).*$/, "", x)
      m = marker(x); if (m == "") return ""
      if (!(m in seen)) { seen[m] = 1; out = out (out == "" ? "" : ", ") "typeof(" m ")" (asm ? ".Assembly" : "") }
      continue
    }
    if (t ~ /^\(?[A-Za-z_][A-Za-z0-9_]*\)?[ \t]*=>/) {
      body = t; sub(/^[^=]*=>[ \t]*/, "", body)
      if (body ~ /^\{.*\}$/) body = substr(body, 2, length(body) - 2)
      ns2 = split(body, st, ";")
      for (j = 1; j <= ns2; j++) {
        s = trim(st[j]); if (s == "") continue
        if (s ~ /^[A-Za-z_][A-Za-z0-9_]*\.LicenseKey[ \t]*=/) continue
        x = ""
        if (s ~ /^[A-Za-z_][A-Za-z0-9_]*\.AddProfile<[A-Za-z0-9_.]+>\(\)$/) { x = s; sub(/^[^<]*</, "", x); sub(/>.*$/, "", x) }
        else if (s ~ /^[A-Za-z_][A-Za-z0-9_]*\.AddProfile\((new [A-Za-z0-9_.]+\(\)|typeof\([A-Za-z0-9_.]+\))\)$/) { x = s; sub(/^[^(]*\((new |typeof\()?/, "", x); sub(/[(].*$|\).*$/, "", x) }
        else if (s ~ /^[A-Za-z_][A-Za-z0-9_]*\.AddMaps\(typeof\([A-Za-z0-9_.]+\)(\.Assembly)?\)$/) { x = s; sub(/^[^(]*\(typeof\(/, "", x); sub(/\).*$/, "", x) }
        if (x == "") return ""
        m = marker(x); if (m == "") return ""
        if (!(m in seen)) { seen[m] = 1; out = out (out == "" ? "" : ", ") "typeof(" m ")" (asm ? ".Assembly" : "") }
      }
      continue
    }
    return ""
  }
  return out
}
BEGIN {
  nr = split(registers, rr, ",")
  for (k = 1; k <= nr; k++) if (split(rr[k], kv, "=") == 2) reg[kv[1]] = kv[2]
}
{ line[NR] = $0; if (!ns && match($0, /^[ \t]*namespace[ \t]+[A-Za-z0-9_.]+/)) { ns = $0; sub(/^[ \t]*namespace[ \t]+/, "", ns); sub(/[^A-Za-z0-9_.].*$/, "", ns) } }
match($0, /[A-Za-z_][A-Za-z0-9_]*\.AssertConfigurationIsValid\(\)/) { v = substr($0, RSTART, RLENGTH); sub(/\..*/, "", v); asserted[v] = 1 }
/^[ \t]*(global[ \t]+)?using[ \t]+AutoMapper[ \t]*;/ { automapper = 1 }
/^[ \t]*(global[ \t]+)?using[ \t]+Microsoft\.Extensions\.Configuration[ \t]*;/ { msconfig = 1 }
END {
  changed = 0
  for (i = 1; i <= NR; i++) {
    s = line[i]; was = s
    # the usings: IMapper, Mapper and TypeAdapterConfig of Mapster in place of those of AutoMapper
    if (s ~ /^[ \t]*(global[ \t]+)?using[ \t]+AutoMapper\.QueryableExtensions[ \t]*;/) sub(/AutoMapper\.QueryableExtensions/, "Mapster", s)
    else if (s ~ /^[ \t]*(global[ \t]+)?using[ \t]+AutoMapper[ \t]*;/) sub(/AutoMapper/, "MapsterMapper", s)
    s = swap(s, "AutoMapper.IMapper", "MapsterMapper.IMapper", "[A-Za-z0-9_.]", "[A-Za-z0-9_]")
    # services.AddAutoMapper(...) -> services.AddMapsterMaps(typeof(<the Registers>))
    if (match(s, /AddAutoMapper\(/)) {
      st0 = RSTART; p = RSTART + RLENGTH - 1; q = close_at(s, p)
      if (q) {
        m = markers(substr(s, p + 1, q - p - 1), 0)
        if (m != "") { s = substr(s, 1, st0 - 1) "AddMapsterMaps(" m ")" substr(s, q + 1); setup = 1 }
      }
    }
    # new MapperConfiguration(cfg => cfg.AddProfile<X>()) -> MapsterSetup.Configure(new TypeAdapterConfig(), <strict
    # when the file asserts the configuration>, typeof(XRegister).Assembly)
    if (match(s, /new[ \t]+MapperConfiguration\(/)) {
      st0 = RSTART; p = RSTART + RLENGTH - 1; q = close_at(s, p)
      if (q) {
        m = markers(substr(s, p + 1, q - p - 1), 1)
        if (m != "") {
          pre = substr(s, 1, st0 - 1); v = ""
          if (match(pre, /[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*$/)) { v = substr(pre, RSTART, RLENGTH); sub(/[ \t]*=.*/, "", v); configs[v] = 1 }
          call = "MapsterSetup.Configure(new TypeAdapterConfig(), " ((v in asserted) ? "true" : "false") ", " m ")"
          rest = substr(s, q + 1)
          if (rest ~ /^\.CreateMapper\(\)/) { call = "new Mapper(" call ")"; rest = substr(rest, 16); mm = 1 }
          else if (rest ~ /^\.AssertConfigurationIsValid\(\)/) {
            call = "MapsterSetup.Configure(new TypeAdapterConfig(), true, " m ").Compile(failFast: false)"; rest = substr(rest, 30)
          }
          s = pre call rest; setup = 1; mapster = 1
        }
      }
    }
    # config.CreateMapper() -> new Mapper(config); config.AssertConfigurationIsValid() -> config.Compile(failFast: false)
    # (config one of those just rewritten: strict, every map of the Registers checked)
    from = 1
    while ((k = index(substr(s, from), ".CreateMapper()")) > 0) {
      p0 = from + k - 1; pre = substr(s, 1, p0 - 1)
      if (match(pre, /[A-Za-z_][A-Za-z0-9_]*$/) && (RSTART == 1 || substr(pre, RSTART - 1, 1) !~ /[A-Za-z0-9_.]/)) {
        v = substr(pre, RSTART, RLENGTH)
        s = substr(pre, 1, RSTART - 1) "new Mapper(" v ")" substr(s, p0 + 15); mm = 1
      } else from = p0 + 1
    }
    if (match(s, /[A-Za-z_][A-Za-z0-9_]*\.AssertConfigurationIsValid\(\)/)) {
      v = substr(s, RSTART, RLENGTH); sub(/\..*/, "", v)
      if ((v in configs) && (RSTART == 1 || substr(s, RSTART - 1, 1) !~ /[A-Za-z0-9_.]/))
        s = substr(s, 1, RSTART - 1) v ".Compile(failFast: false)" substr(s, RSTART + RLENGTH)
    }
    # query.ProjectTo<D>(mapper.ConfigurationProvider) -> query.ProjectToType<D>(mapper.Config);
    # mapper.ProjectTo<D>(query) -> query.ProjectToType<D>(mapper.Config); with more arguments: left as it is
    from = 1
    while ((k = index(substr(s, from), ".ProjectTo<")) > 0) {
      p0 = from + k - 1; a0 = p0 + 10; a1 = close_at(s, a0)
      if (!a1 || substr(s, a1 + 1, 1) != "(") { from = p0 + 1; continue }
      c1 = close_at(s, a1 + 1)
      if (!c1) { from = p0 + 1; continue }
      T = substr(s, a0, a1 - a0 + 1); n = split_args(substr(s, a1 + 2, c1 - a1 - 2), arg)
      pre = substr(s, 1, p0 - 1); recv = ""
      if (match(pre, /[A-Za-z_@][A-Za-z0-9_.]*$/)) recv = substr(pre, RSTART, RLENGTH)
      if (n == 1 && recv ~ /[Mm]apper$/ && arg[1] !~ /ConfigurationProvider$/) {
        qy = chain_ok(arg[1]) ? arg[1] : "(" arg[1] ")"
        s = substr(pre, 1, length(pre) - length(recv)) qy ".ProjectToType" T "(" recv ".Config)" substr(s, c1 + 1)
        mapster = 1
      } else if (n <= 1) {
        a = (n == 1 ? arg[1] : ""); sub(/\.ConfigurationProvider$/, ".Config", a)
        s = pre ".ProjectToType" T "(" a ")" substr(s, c1 + 1)
        mapster = 1
      }
      from = p0 + 1
    }
    # the configuration of AutoMapper as a member or a type: that of Mapster
    s = swap(s, ".ConfigurationProvider", ".Config", "", "[A-Za-z0-9_]")
    if (s !~ /new[ \t]+MapperConfiguration/) { t = s; s = swap(s, "MapperConfiguration", "TypeAdapterConfig", "[A-Za-z0-9_.]", "[A-Za-z0-9_(]"); if (s != t) mapster = 1 }
    if (automapper && !msconfig) { t = s; s = swap(s, "IConfigurationProvider", "TypeAdapterConfig", "[A-Za-z0-9_.]", "[A-Za-z0-9_]"); if (s != t) mapster = 1 }
    if (s != was) changed++
    out[i] = s
  }
  # the usings the code now needs (Mapster: ProjectToType, TypeAdapterConfig; MapsterMapper: Mapper; the namespace of
  # MapsterSetup), each once
  last = 0
  for (i = 1; i <= NR; i++) {
    if (out[i] ~ /^[ \t]*(global[ \t]+)?using[ \t]+[A-Za-z0-9_.]+[ \t]*;/) {
      u = out[i]; gsub(/[ \t]/, "", u)
      if (u in have) { out[i] = "\001"; changed++ } else { have[u] = 1; last = i }
    } else if (out[i] !~ /^[ \t]*(\/\/.*)?$/) break
  }
  add = ""
  if (mapster && !("usingMapster;" in have) && !("globalusingMapster;" in have)) add = add "using Mapster;\n"
  if (mm && !("usingMapsterMapper;" in have) && !("globalusingMapsterMapper;" in have)) add = add "using MapsterMapper;\n"
  if (setup && setupns != "" && index(ns ".", setupns ".") != 1 && !(("using" setupns ";") in have)) add = add "using " setupns ";\n"
  if (add != "") changed++
  if (last == 0 && add != "") printf "%s\n", add
  for (i = 1; i <= NR; i++) {
    if (out[i] != "\001") print out[i]
    if (i == last && add != "") printf "%s", add
  }
  print "@CHANGED " changed
}
AWK
  # the files of the code that use AutoMapper, its profiles and their resolvers left out (they leave with AutoMapper)
  cs_files "$folder" | grep -v -E '(^|/)(bin|obj)/' > "$tmp/files"
  : > "$tmp/candidates"
  n=0 skipped=0
  while IFS= read -r f; do
    grep -q -E 'AutoMapper|ProjectTo<|AddAutoMapper|MapperConfiguration|CreateMapper\(\)' "$f" 2>/dev/null || continue
    # a Register of Mapster (the quote of a map left to finish names AutoMapper): scaffold's, not the code that maps
    grep -q -E 'class[[:space:]]+[A-Za-z0-9_]+[[:space:]]*:[[:space:]]*IRegister' "$f" && continue
    if grep -q -E '(^|[^A-Za-z0-9_])CreateMap[<(]|I(Value|MemberValue)Resolver<|ITypeConverter<|IValueConverter<|IMappingAction<' "$f"; then
      skipped=$((skipped + 1))
      continue
    fi
    printf '%s\n' "$f" >> "$tmp/candidates"
    awk -v setupns="$setupns" -v registers="$registers" -f "$tmp/switch.awk" "$f" > "$tmp/out" || { echo "STOP: the rewrite of $f failed: nothing changed in it"; continue; }
    c=$(sed -n 's/^@CHANGED //p' "$tmp/out")
    [ "${c:-0}" -gt 0 ] || continue
    grep -v '^@CHANGED ' "$tmp/out" > "$tmp/new"
    cat "$tmp/new" > "$f"
    n=$((n + 1))
    echo "SWITCHED: $f — $c line(s)"
  done < "$tmp/files"
  # what stays by hand in these files: the check of AutoMapper, on them only
  : > "$tmp/left"
  if [ -s "$tmp/candidates" ]; then
    tr '\n' '\0' < "$tmp/candidates" | xargs -0 grep -n -H -E '^[[:space:]]*(global[[:space:]]+)?using[[:space:]]+(static[[:space:]]+)?AutoMapper|AddAutoMapper|MapperConfiguration|\.ProjectTo<|AssertConfigurationIsValid|CreateMapper\(\)|IMappingOperationOptions|\.Items\[|ResolutionContext|AutoMapper\.' 2>/dev/null |
      sed -E 's/^([^:]*:[0-9]+):[[:space:]]*/LEFT: \1 /' | cut -c1-240 > "$tmp/left"
    cat "$tmp/left"
  fi
  nl=$(grep -c . "$tmp/left")
  echo "SWITCH: $n file(s) rewritten for Mapster (the usings, ProjectTo into ProjectToType, AddAutoMapper into AddMapsterMaps, the configurations of the tests), $nl line(s) left by hand (the skill mapster), $skipped profile or resolver file(s) left out (they leave with AutoMapper); next: the build, then the profiles, resolvers and packages of AutoMapper removed until automapper.sh check says AUTOMAPPER: GONE"
  exit 0
fi

# ---------- helpers ----------
if [ "$action" = helpers ]; then
  project=$(from_root "$1")
  [ -n "$project" ] && [ -f "$project" ] || { echo "STOP: automapper.sh helpers <the test project .csproj>"; exit 1; }
  ns=$(sed -n -E 's/.*<RootNamespace>([^<]*)<.*/\1/p' "$project" | head -n 1)
  [ -n "$ns" ] || ns=$(basename "$project" .csproj | tr -- '-' '_')
  ns="$ns.Mapping"
  file="$(dirname "$project")/Mapping/MappingSnapshot.cs"
  file=${file#./}
  if [ -f "$file" ]; then
    echo "KEPT: $file (exists: the tests own it)"
  else
    mkdir -p "$(dirname "$file")"
    sed "s/__NAMESPACE__/$ns/" > "$file" <<'EOF'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace __NAMESPACE__;

// The helpers of the snapshot tests of the maps (written by automapper.sh helpers, the skill automapper; the tests own
// them, never changed).

// A source whose every member has a value of its own (seed: another set of values); nulls: its members that may be
// null left null (string?, Customer?, int?), the others filled. Abstract types: their concrete types in turn.
public static class MappingSample
{
    public static T Create<T>(int seed = 1, bool nulls = false) => (T)Build(typeof(T), "", seed, nulls, new HashSet<Type>())!;

    private static object? Build(Type type, string member, int seed, bool nulls, HashSet<Type> path)
    {
        var n = seed * 100 + member.Sum(c => c) % 97;
        type = Nullable.GetUnderlyingType(type) ?? type;
        if (type == typeof(string)) return $"{member}-{seed}";
        if (type == typeof(bool)) return seed % 2 == 1;
        if (type == typeof(char)) return (char)('A' + n % 26);
        if (type == typeof(byte) || type == typeof(sbyte)) return Convert.ChangeType(n % 100, type, CultureInfo.InvariantCulture);
        if (type == typeof(decimal) || type == typeof(double) || type == typeof(float)) return Convert.ChangeType(n + 0.25m, type, CultureInfo.InvariantCulture);
        if (type.IsPrimitive) return Convert.ChangeType(n, type, CultureInfo.InvariantCulture);
        if (type == typeof(Guid)) return new Guid(n, 0, 0, new byte[8]);
        if (type == typeof(DateTime)) return new DateTime(2026, 1, 1, 8, 30, 0, DateTimeKind.Utc).AddDays(n);
        if (type == typeof(DateTimeOffset)) return new DateTimeOffset(2026, 1, 1, 8, 30, 0, TimeSpan.Zero).AddDays(n);
        if (type == typeof(DateOnly)) return new DateOnly(2026, 1, 1).AddDays(n);
        if (type == typeof(TimeOnly)) return new TimeOnly(8, 30).AddMinutes(n);
        if (type == typeof(TimeSpan)) return TimeSpan.FromMinutes(n);
        if (type == typeof(Uri)) return new Uri($"https://example.com/{member}/{seed}");
        if (type.IsEnum)
        {
            var values = Enum.GetValues(type);
            return values.GetValue(Math.Min(1, values.Length - 1)); // the second value: never the default by chance
        }

        if (type.IsArray)
        {
            var items = Items(type.GetElementType()!, member, seed, nulls, path);
            var array = Array.CreateInstance(type.GetElementType()!, items.Count);
            items.CopyTo(array, 0);
            return array;
        }

        if (type.IsGenericType && typeof(IEnumerable).IsAssignableFrom(type))
        {
            var arguments = type.GetGenericArguments();
            if (arguments.Length == 2)
            {
                var dictionary = (IDictionary)Activator.CreateInstance(typeof(Dictionary<,>).MakeGenericType(arguments))!;
                for (var i = 0; i < 2; i++) dictionary[Build(arguments[0], member, seed + i, false, path)!] = Build(arguments[1], member, seed + i, nulls, path);
                return dictionary;
            }

            var list = Items(arguments[0], member, seed, nulls, path);
            return type.IsAssignableFrom(list.GetType())
                ? list
                : Activator.CreateInstance(type.IsInterface ? typeof(HashSet<>).MakeGenericType(arguments) : type, list);
        }

        if (type.IsAbstract || type.IsInterface)
        {
            var concrete = type.Assembly.GetTypes()
                .Where(t => t is { IsAbstract: false, IsInterface: false, ContainsGenericParameters: false } && type.IsAssignableFrom(t))
                .OrderBy(t => t.FullName, StringComparer.Ordinal)
                .ToList();
            return concrete.Count == 0 ? null : Build(concrete[(seed - 1) % concrete.Count], member, seed, nulls, path);
        }

        if (!path.Add(type)) return null; // a cycle: left null
        try
        {
            var context = new NullabilityInfoContext();
            var constructor = type.GetConstructor(Type.EmptyTypes)
                ?? type.GetConstructors().OrderByDescending(c => c.GetParameters().Length).FirstOrDefault();
            var parameters = constructor?.GetParameters() ?? Array.Empty<ParameterInfo>();
            var target = constructor is null
                ? Activator.CreateInstance(type)!
                : constructor.Invoke(parameters.Select(p => Value(p.ParameterType, p.Name!, context.Create(p).WriteState, seed, nulls, path)).ToArray());
            foreach (var property in type.GetProperties(BindingFlags.Public | BindingFlags.Instance))
            {
                if (property.GetIndexParameters().Length > 0 || parameters.Any(p => string.Equals(p.Name, property.Name, StringComparison.OrdinalIgnoreCase)))
                    continue;
                if (property.SetMethod is null && !typeof(IList).IsAssignableFrom(property.PropertyType))
                    continue;
                var value = Value(property.PropertyType, property.Name, context.Create(property).WriteState, seed, nulls, path);
                if (property.SetMethod is not null)
                    property.SetValue(target, value);
                else if (value is IEnumerable items && property.GetValue(target) is IList { IsReadOnly: false } existing)
                    foreach (var item in items) existing.Add(item);
            }

            return target;
        }
        finally
        {
            path.Remove(type);
        }
    }

    private static object? Value(Type type, string member, NullabilityState state, int seed, bool nulls, HashSet<Type> path) =>
        nulls && (state == NullabilityState.Nullable || Nullable.GetUnderlyingType(type) is not null)
            ? null
            : Build(type, member, seed, nulls, path);

    private static IList Items(Type element, string member, int seed, bool nulls, HashSet<Type> path)
    {
        var list = (IList)Activator.CreateInstance(typeof(List<>).MakeGenericType(element))!;
        for (var i = 0; i < 2; i++) list.Add(Build(element, member, seed + i, nulls, path));
        return list;
    }
}

// What a map gives, compared with its golden file Mapping/Snapshots/<name>.json of the test project. MAPPING_RECORD=1
// (automapper.sh record): a golden file that does not exist yet is written; one that exists is never written again.
public static class MappingSnapshot
{
    public static void Verify(object? actual, string name, [CallerFilePath] string caller = "")
    {
        var json = Json(actual);
        var file = Path.Combine(Folder(caller), name + ".json");
        if (!File.Exists(file))
        {
            if (Environment.GetEnvironmentVariable("MAPPING_RECORD") != "1")
                throw new InvalidOperationException($"No golden file {file}: it is recorded on AutoMapper, before the mapper changes (automapper.sh record)");
            Directory.CreateDirectory(Path.GetDirectoryName(file)!);
            File.WriteAllText(file, json + "\n");
            return;
        }

        var expected = File.ReadAllText(file).Replace("\r\n", "\n").TrimEnd('\n').Split('\n');
        var lines = json.Split('\n');
        for (var i = 0; i < Math.Max(expected.Length, lines.Length); i++)
        {
            var want = i < expected.Length ? expected[i] : "(the end)";
            var got = i < lines.Length ? lines[i] : "(the end)";
            if (want == got) continue;
            var around = string.Join("\n", lines.Skip(Math.Max(0, i - 4)).Take(8));
            throw new InvalidOperationException($"{name}: line {i + 1} of {file}\n  expected: {want.Trim()}\n  actual:   {got.Trim()}\nThe result around it:\n{around}");
        }
    }

    // Each member, sorted by name, with the type of each object: the same text on every machine (invariant culture,
    // dates in ISO 8601)
    public static string Json(object? value)
    {
        var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer, new JsonWriterOptions { Indented = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping }))
            Write(writer, value, new HashSet<object>(ReferenceEqualityComparer.Instance), 0);
        return Encoding.UTF8.GetString(buffer.ToArray()).Replace("\r\n", "\n");
    }

    private static void Write(Utf8JsonWriter w, object? value, HashSet<object> parents, int depth)
    {
        if (value is null)
        {
            w.WriteNullValue();
            return;
        }

        switch (value)
        {
            case string s: w.WriteStringValue(s); return;
            case bool b: w.WriteBooleanValue(b); return;
            case char c: w.WriteStringValue(c.ToString()); return;
            case Enum e: w.WriteStringValue(e.ToString()); return;
            case decimal m: w.WriteNumberValue(m); return;
            case double or float: w.WriteStringValue(Convert.ToString(value, CultureInfo.InvariantCulture)); return;
            case IFormattable f when f.GetType().IsPrimitive: w.WriteRawValue(f.ToString(null, CultureInfo.InvariantCulture)); return;
            case DateTime d: w.WriteStringValue(d.ToString("O", CultureInfo.InvariantCulture)); return;
            case DateTimeOffset d: w.WriteStringValue(d.ToString("O", CultureInfo.InvariantCulture)); return;
            case DateOnly d: w.WriteStringValue(d.ToString("O", CultureInfo.InvariantCulture)); return;
            case TimeOnly t: w.WriteStringValue(t.ToString("O", CultureInfo.InvariantCulture)); return;
            case TimeSpan t: w.WriteStringValue(t.ToString("c", CultureInfo.InvariantCulture)); return;
            case Guid or Uri or Version: w.WriteStringValue(Convert.ToString(value, CultureInfo.InvariantCulture)); return;
            case IDictionary dictionary:
                w.WriteStartObject();
                foreach (var key in dictionary.Keys.Cast<object>().OrderBy(k => Convert.ToString(k, CultureInfo.InvariantCulture), StringComparer.Ordinal))
                {
                    w.WritePropertyName(Convert.ToString(key, CultureInfo.InvariantCulture) ?? "");
                    Write(w, dictionary[key], parents, depth + 1);
                }

                w.WriteEndObject();
                return;
            case IEnumerable items:
                w.WriteStartArray();
                foreach (var item in items) Write(w, item, parents, depth + 1);
                w.WriteEndArray();
                return;
        }

        var type = value.GetType();
        if (depth > 10 || (!type.IsValueType && !parents.Add(value)))
        {
            w.WriteStringValue($"(a cycle: {type.Name})");
            return;
        }

        w.WriteStartObject();
        w.WriteString("$type", type.Name);
        foreach (var property in type.GetProperties(BindingFlags.Public | BindingFlags.Instance)
                     .Where(p => p.GetIndexParameters().Length == 0 && p.GetGetMethod() is not null)
                     .OrderBy(p => p.Name, StringComparer.Ordinal))
        {
            w.WritePropertyName(property.Name);
            Write(w, property.GetValue(value), parents, depth + 1);
        }

        w.WriteEndObject();
        if (!type.IsValueType) parents.Remove(value);
    }

    // <the test project>/Mapping/Snapshots: the first folder with a .csproj above the test binaries, or above the test file
    private static string Folder(string caller)
    {
        foreach (var start in new[] { AppContext.BaseDirectory, Path.GetDirectoryName(caller) })
        {
            for (var dir = string.IsNullOrEmpty(start) ? null : new DirectoryInfo(start); dir is not null; dir = dir.Parent)
            {
                if (dir.Exists && dir.EnumerateFiles("*.csproj").Any())
                    return Path.Combine(dir.FullName, "Mapping", "Snapshots");
            }
        }

        throw new InvalidOperationException($"No test project above {AppContext.BaseDirectory}");
    }
}
EOF
    echo "WRITTEN: $file"
  fi
  echo "HELPERS: $file, namespace $ns: MappingSample.Create<T>(seed, nulls) (a source whose every member has a value of its own; nulls: those that may be null left null), MappingSnapshot.Verify(result, name) (compared with Mapping/Snapshots/<name>.json); then the tests of the maps and the adapter Mapped on AutoMapper (the skill automapper), and automapper.sh record"
  exit 0
fi

# ---------- record ----------
if [ "$action" = record ]; then
  project=$(from_root "$1") filter=${2:-FullyQualifiedName~Mapping}
  [ -n "$project" ] && [ -f "$project" ] || { echo "STOP: automapper.sh record <the test project .csproj> [<filter>]"; exit 1; }
  dir=$(dirname "$project")
  # a committed golden file changed and not committed: the contract is the committed one, never an edit
  edited=$(git diff --name-only HEAD -- "$dir" 2>/dev/null | grep -E '/Snapshots/[^/]+\.json$' | tr '\n' ' ' | sed 's/ $//')
  if [ -n "$edited" ]; then
    echo "STOP: golden files committed and changed since ($edited): the contract of the maps is the committed version, never edited (git checkout -- <file> puts it back); nothing recorded"
    exit 1
  fi
  # the golden files there already, committed or not, kept as they are: never written again
  snapshots() { git ls-files --cached --others --exclude-standard -- "$dir" | grep -E '/Snapshots/[^/]+\.json$' | sort -u; }
  snapshots > "$tmp/before"
  mkdir -p "$tmp/kept"
  while IFS= read -r f; do mkdir -p "$tmp/kept/$(dirname "$f")" && cp "$f" "$tmp/kept/$f"; done < "$tmp/before"
  out=$(MAPPING_RECORD=1 sh "$here/build-test.sh" "$project" --filter "$filter" 2>&1)
  status=$?
  snapshots | comm -13 "$tmp/before" - > "$tmp/new"
  changed=""
  while IFS= read -r f; do
    cmp -s "$f" "$tmp/kept/$f" 2>/dev/null && continue
    cp "$tmp/kept/$f" "$f" 2>/dev/null
    changed="$changed${changed:+ }$f"
  done < "$tmp/before"
  if [ -n "$changed" ]; then
    tr '\n' '\0' < "$tmp/new" | xargs -0 rm -f
    echo "STOP: the tests wrote golden files that were there already ($changed): never recorded again (MappingSnapshot.Verify of the skill never does); put back as they were, nothing recorded"
    exit 1
  fi
  if [ "$status" -ne 0 ] || ! printf '%s\n' "$out" | grep -q '^TESTS: OK'; then
    tr '\n' '\0' < "$tmp/new" | xargs -0 rm -f
    printf '%s\n' "$out" | tail -n 30
    echo "STOP: the snapshot tests do not pass on AutoMapper: nothing recorded"
    exit 1
  fi
  sed 's/^/RECORDED: /' "$tmp/new"
  echo "RECORD: $(grep -c . "$tmp/new") golden file(s) written from AutoMapper ($filter); then the tests green twice, and sealed with their golden files"
  exit 0
fi
