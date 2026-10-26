#!/bin/sh
# AutoMapper replaced by Mapperly (the skill automapper): the mappings generated at build time, plain C# with no runtime
# package and no reflection, each target member mapped or ignored by name (a member forgotten fails the build). What
# Qwen should not work out by hand, done the same way every time.
#   inventory [<folder>]     read only: the AutoMapper packages and their version, and Mapperly when it is there; each
#                            profile (in the order to replace them: the simplest first), each of its maps
#                            (CreateMap<Source, Destination>, its line, the options it uses); the projects to set up; the
#                            converters and resolvers (and whether they take services); the global settings that change
#                            every map (naming conventions, null collections, value transformers…); where the code maps
#                            (Map<T>, a map onto an existing object, ProjectTo, the runtime type forms, IMapper injected),
#                            registers (AddAutoMapper) and tests AutoMapper (AssertConfigurationIsValid, Mock<IMapper>);
#                            the Mapperly equivalent of each option used; the plan.
#   setup <project>          once the developer agreed: Riok.Mapperly in the project (compile time only: ExcludeAssets
#                            runtime, PrivateAssets all; Directory.Packages.props when versions are central), the
#                            diagnostics of a mapping left incomplete or ambiguous as errors (Mapperly.globalconfig), and
#                            MapperDefaults.cs, the rules of every mapper of the project, as AutoMapper mapped; C# 9 at
#                            least (LangVersion latest for a netstandard or .NET Framework target without one); then the
#                            build. A build that fails: every file put back as it was, nothing changed.
#   scaffold <profile file>  the mapper of a profile next to it (<Name>Profile.cs -> <Name>Mapper.cs, same namespace): a
#                            static partial class (an instance class, their services in its constructor, when resolvers
#                            of the profile take some), one method per map (To<Destination>, the way back of a
#                            ReverseMap To<Source>), each map of AutoMapper quoted above its method, to translate then
#                            take out; never written over an existing file.
#   helpers <test project>   the helpers of the snapshot tests of the maps, once: Mapping/MappingSnapshot.cs of the test
#                            project (MappingSample.Create<T>, a source whose every member has a value of its own, and
#                            MappingSnapshot.Verify, what a map gives compared with its golden file); never written over.
#   record <test project> [<filter>]
#                            the golden files of the snapshot tests (Mapping/Snapshots/*.json), written from what
#                            AutoMapper gives (MAPPING_RECORD=1, the tests of the filter, FullyQualifiedName~Mapping by
#                            default); a golden file there already is never written again: it is the contract the
#                            generated mapper must meet (a committed one edited since: STOP). Tests that fail: nothing
#                            recorded.
#   check [<folder>]         read only: what is left of AutoMapper, each with its file and line (a quote of a map left in
#                            a comment included); "AUTOMAPPER: GONE" when nothing is left (the Markdown documentation
#                            excepted), exit 1 otherwise.
# Output: "INVENTORY:", "PACKAGE:", "PROFILE:", "MAP:", "PROJECTS:", "CONVERTER:", "GLOBAL:", "CALL:", "REGISTRATION:",
# "TEST:", "EQUIVALENT:", "PLAN:" (inventory); "SETUP:" (setup); "SCAFFOLD:", "WRITTEN:"/"KEPT:", "METHOD:", "NEXT:"
# (scaffold); "WRITTEN:"/"KEPT:", "HELPERS:" (helpers); "RECORDED:", "RECORD:" (record); "LEFT:" lines and
# "AUTOMAPPER: GONE" or "AUTOMAPPER: <n> place(s) left" (check); "STOP:" when something is wrong.
# Usage: mapperly.sh inventory [<folder>] | setup <project> | scaffold <profile file> | helpers <test project>
#        | record <test project> [<filter>] | check [<folder>]

LC_ALL=C
export LC_ALL
here=$(cd "$(dirname "$0")" && pwd)
start=$PWD
action=$1
[ $# -gt 0 ] && shift
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "STOP: not a git repository"; exit 1; }
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/mapperly.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
MAPPERLY_DEFAULT=4.3.1
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
  inventory|check|setup|scaffold|helpers|record) ;;
  *) echo "STOP: mapperly.sh inventory [<folder>] | setup <project> | scaffold <profile file> | helpers <test project> | record <test project> [<filter>] | check [<folder>]"; exit 1 ;;
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
  git grep --untracked -n -E '(^|[^A-Za-z0-9_])IMapper([^A-Za-z0-9_]|$)|I(Value|MemberValue)Resolver<|ITypeConverter<|IValueConverter<|IMappingAction<|AutoMapper\.' -- ${folder:+"$folder"} '*.cs' 2>/dev/null |
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
    while IFS="$(printf '\t')" read -r first last text; do
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
      echo "PROJECTS: $todo (Riok.Mapperly to add, once the developer agreed: mapperly.sh setup <each>)"
    else
      echo "PROJECTS: $(tr '\n' ' ' < "$tmp/projects" | sed 's/ $//') (Mapperly already set up)"
    fi
  fi
  # the converters, resolvers and actions: a class each, and whether it takes services (the mapper then is an instance)
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
  done < "$tmp/files"
  git grep --untracked -n -E 'AllowNullCollections|AllowNullDestinationValues|SourceMemberNamingConvention|DestinationMemberNamingConvention|ShouldMapProperty|ShouldMapField|ShouldMapMethod|ShouldUseConstructor|AddGlobalIgnore|ValueTransformers|ForAllMaps|ForAllPropertyMaps|RecognizePrefixes|RecognizePostfixes|RecognizeDestinationPrefixes|RecognizeDestinationPostfixes|ClearPrefixes|ReplaceMemberName|DisableConstructorMapping|EnableNullPropagationForQueryMapping|AddMaps\(|Internal\(\)' -- ${folder:+"$folder"} '*.cs' 2>/dev/null |
    sed -E 's/^([^:]*:[0-9]+):[[:space:]]*(.*)$/GLOBAL: \1 \2 (it changes how every map behaves: the snapshot tests show it, the skill says its equivalent)/' | cut -c1-260
  # where the code maps with AutoMapper: the files that name it, the profiles left out
  cut -f1 "$tmp/maps" | sort -u > "$tmp/mapfiles"
  git grep --untracked -l -E '(^|[^A-Za-z0-9_])IMapper([^A-Za-z0-9_]|$)|using[[:space:]]+AutoMapper|ProjectTo<' -- ${folder:+"$folder"} '*.cs' 2>/dev/null | grep -v -x -F -f "$tmp/mapfiles" > "$tmp/users"
  if [ -s "$tmp/users" ]; then
    tr '\n' '\0' < "$tmp/users" | xargs -0 grep -n -H -E '\.ProjectTo<|\.Map<|\.Map\(|(^|[^A-Za-z0-9_])IMapper([^A-Za-z0-9_]|$)' 2>/dev/null |
      awk '{
        text = $0; sub(/^[^:]*:[0-9]+:[[:space:]]*/, "", text)
        split($0, f, ":")
        kind = "IMapper"
        if (text ~ /Mock<IMapper>|Substitute\.For<IMapper>/) kind = "a test double of IMapper (the test maps for real once the class no longer takes IMapper)"
        else if (text ~ /\.ProjectTo</) kind = "ProjectTo (an IQueryable projection: a projection method of the mapper, never a Map after ToList)"
        else if (text ~ /\.Map<[^>]*>\(/) kind = "Map<T> (a new object: To<T>())"
        else if (text ~ /\.Map\([^,()]*,[^,()]*,/) kind = "Map(source, sourceType, destinationType) (the runtime type: a typed call, or a runtime target type method)"
        else if (text ~ /\.Map\([^,()]*,[^,()]*\)/) kind = "Map(source, destination) (onto an existing object: a void method of the mapper)"
        else if (text ~ /\.Map\(/) kind = "Map(...)"
        else if (text ~ /IMapper[ \t]+[A-Za-z_]+[ \t]*[,)]|\(IMapper[ \t]/) kind = "IMapper injected (removed once the class maps no more with it; an instance mapper injected instead)"
        printf "CALL: %s:%s %s — %s\n", f[1], f[2], kind, substr(text, 1, 120)
      }'
  fi
  git grep --untracked -n -E 'AddAutoMapper|new MapperConfiguration' -- ${folder:+"$folder"} '*.cs' 2>/dev/null | sed -E 's/^([^:]*:[0-9]+):[[:space:]]*(.*)$/REGISTRATION: \1 \2/' | cut -c1-220
  git grep --untracked -n -E 'AssertConfigurationIsValid|Mock<IMapper>|Substitute\.For<IMapper>' -- ${folder:+"$folder"} '*.cs' 2>/dev/null | sed -E 's/^([^:]*:[0-9]+):[[:space:]]*(.*)$/TEST: \1 \2/' | cut -c1-220
  sort -u "$tmp/used" | while IFS= read -r opt; do
    case "$opt" in
      ForMember) eq="one attribute per member, on the method of the map" ;;
      MapFrom) eq="a path: [MapProperty(\"Customer.Name\", nameof(D.X))]; one source member through code: [MapProperty(nameof(S.Y), nameof(D.X), Use = nameof(Helper))]; an expression on the source: [MapPropertyFromSource(nameof(D.X), Use = nameof(Helper))] (a private static helper, no attribute)" ;;
      Ignore) eq="[MapperIgnoreTarget(nameof(D.X))]" ;;
      ReverseMap) eq="a second method the other way (To<Source>), with its own attributes; the unflattening by hand: [MapProperty(nameof(D.CustomerName), \"Customer.Name\")]" ;;
      BeforeMap|AfterMap) eq="a public method around a private partial void one: new target, the BeforeMap code, the generated method onto it, the AfterMap code; [UserMapping(Default = true)] on it" ;;
      Condition|PreCondition) eq="in the method around the generated one: if (condition) target.X = ...; and [MapperIgnoreTarget(nameof(D.X))]" ;;
      ConvertUsing) eq="the whole conversion of a type pair: a [UserMapping(Default = true)] method; of one member (IValueConverter): [MapProperty(source, target, Use = nameof(Method))]" ;;
      ConstructUsing) eq="[ObjectFactory] method (it builds the target, Mapperly maps the rest), or a [UserMapping(Default = true)] method that builds it all" ;;
      Include|IncludeBase|IncludeAllDerived) eq="[MapDerivedType<Source, Destination>] on the method of the base types, one per derived pair; [IncludeMappingConfiguration(nameof(Base))] to reuse the attributes of the base map" ;;
      IncludeMembers) eq="[MapNestedProperties(nameof(S.Member))]" ;;
      NullSubstitute) eq="[MapProperty(source, target, Use = nameof(OrDefault))], OrDefault(T? value) => value ?? substitute" ;;
      ForCtorParam) eq="[MapProperty(source, \"param\")] or [MapPropertyFromSource(\"param\", Use = ...)]: constructor parameters matched by name, case ignored" ;;
      ForPath) eq="[MapProperty(source, \"Nested.Member\")]" ;;
      MaxDepth|PreserveReferences) eq="[Mapper(UseReferenceHandling = true)] for cycles (its runtime assets then: no ExcludeAssets runtime); a depth limit: a user method" ;;
      UseDestinationValue) eq="[MapperIgnoreTarget(nameof(D.X))] on the void method: the value of the target is kept" ;;
      ForAllMembers|ForSourceMember|ValidateMemberList|MemberList) eq="the strategy of the method: [MapperRequiredMapping(RequiredMappingStrategy.Source)] (every source member mapped), Target (the default of MapperDefaults.cs); ForAllMembers(Condition(srcMember != null)): a mapper of its own, [Mapper(AllowNullPropertyAssignment = false)]" ;;
      AddTransform) eq="no global value transformer in Mapperly: a Use helper on each member concerned, or the method around the generated one" ;;
      DisableCtorValidation|ExplicitExpansion|As) eq="no direct equivalent: see the skill automapper" ;;
      "a resolver/converter/action class") eq="its code moves into a method of the mapper (an instance mapper, its services in its constructor, when it takes some)" ;;
      *) eq="see the skill automapper" ;;
    esac
    echo "EQUIVALENT: $opt -> $eq"
  done
  if [ "$nm" -gt 0 ]; then
    echo "PLAN: the developer's answer first (« Mapperly » : mapperly.sh setup <each project of the PROJECTS line>, a first commit); then one profile per step in the order of the PROFILE lines, each « (filet d'abord) » (the snapshot tests of its maps, recorded on AutoMapper: mapperly.sh record) and « (s'appuyer sur le skill automapper) » (its mapper: mapperly.sh scaffold <profile file>, then its callers); the last step removes AutoMapper (packages, profiles, AddAutoMapper, IMapper, its tests) until mapperly.sh check says AUTOMAPPER: GONE"
  else
    echo "PLAN: no map of AutoMapper; mapperly.sh check says what may be left (packages, registrations, IMapper)"
  fi
  exit 0
fi

# ---------- setup ----------
cache_best() {
  cache=${NUGET_PACKAGES:-$HOME/.nuget/packages}
  for d in "$cache/riok.mapperly"/*; do [ -d "$d" ] && basename "$d"; done | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
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

if [ "$action" = setup ]; then
  target=$(from_root "$1")
  [ -n "$target" ] || { echo "STOP: mapperly.sh setup <the project of the profiles, or its folder>"; exit 1; }
  case "$target" in
    *.csproj) csproj=$target ;;
    *) csproj=$(find "$target" -maxdepth 1 -name '*.csproj' 2>/dev/null | sort | head -n 1) ;;
  esac
  [ -n "$csproj" ] && [ -f "$csproj" ] || { echo "STOP: no .csproj in $1"; exit 1; }
  csproj=$(printf '%s' "$csproj" | sed 's:^\./::')
  grep -q '<Project Sdk=' "$csproj" || { echo "STOP: $csproj is not an SDK-style project: Mapperly is a source generator, it needs one (and C# 9)"; exit 1; }
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
  v=$(newer "$(cache_best)" "$MAPPERLY_DEFAULT")
  done_what=""
  if grep -qi 'Include="Riok.Mapperly"' "$csproj"; then
    done_what="Riok.Mapperly already in $csproj"
  else
    attrs=' ExcludeAssets="runtime" PrivateAssets="all"'
    if [ -n "$props" ]; then
      grep -qi '<PackageVersion[^>]*Include="Riok.Mapperly"' "$props" ||
        awk -v v="$v" '
          function line() { return "    <PackageVersion Include=\"Riok.Mapperly\" Version=\"" v "\" />" }
          !done && /<PackageVersion / { seen = 1 }
          !done && seen && /<\/ItemGroup>/ { print line(); done = 1 }
          !done && /<\/Project>/ { print "  <ItemGroup>"; print line(); print "  </ItemGroup>"; done = 1 }
          { print }' "$props" > "$tmp/props.new" && cat "$tmp/props.new" > "$props"
      ref="    <PackageReference Include=\"Riok.Mapperly\"$attrs />"
    else
      ref="    <PackageReference Include=\"Riok.Mapperly\" Version=\"$v\"$attrs />"
    fi
    awk -v ref="$ref" '
      !done && /<PackageReference / { seen = 1 }
      !done && seen && /<\/ItemGroup>/ { print ref; done = 1 }
      !done && /<\/Project>/ { print "  <ItemGroup>"; print ref; print "  </ItemGroup>"; print ""; done = 1 }
      { print }' "$csproj" > "$tmp/csproj.new" && cat "$tmp/csproj.new" > "$csproj"
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
        print "    <!-- Mapperly: a mapping left incomplete or ambiguous fails the build (mapperly.sh setup) -->"
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
      echo "# Mapperly (written by mapperly.sh setup; the application owns it): what would map wrong or not at all fails the"
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

// The rules of every Mapperly mapper of this project, as AutoMapper mapped (written by mapperly.sh setup; the
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
if [ "$action" = scaffold ]; then
  file=$(from_root "$1")
  [ -n "$file" ] && [ -f "$file" ] || { echo "STOP: mapperly.sh scaffold <the .cs file of a profile>"; exit 1; }
  statements "$file" > "$tmp/st"
  [ -s "$tmp/st" ] || { echo "STOP: no CreateMap in $file"; exit 1; }
  profile=$(grep -o -E 'class[[:space:]]+[A-Za-z0-9_]+' "$file" | head -n 1 | sed -E 's/class[[:space:]]+//')
  name=$(printf '%s' "$profile" | sed -E 's/(Mapping)?Profile$//')
  [ -n "$name" ] || name=$profile
  mapper="$(dirname "$file")/${name}Mapper.cs"
  mapper=${mapper#./}
  ns=$(sed -n -E 's/^[[:space:]]*namespace[[:space:]]+([A-Za-z0-9_.]+).*/\1/p' "$file" | head -n 1)
  # the resolvers, converters and actions of its maps that take services: the mapper is then an instance class, those
  # services in its constructor (registered in place of AddAutoMapper, injected where IMapper was)
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
  echo "SCAFFOLD: $mapper (${name}Mapper, namespace ${ns:-global}) from $profile, $(grep -c . "$tmp/st") map(s)${services:+; an instance mapper: its resolvers take $services}"
  if [ -f "$mapper" ]; then
    echo "KEPT: $mapper (exists: the application owns it)"
    exit 0
  fi
  {
    { echo "using Riok.Mapperly.Abstractions;"; grep -E '^[[:space:]]*using[[:space:]]' "$file" | grep -v -E 'AutoMapper' | sed 's/^[[:space:]]*//'; } |
      sort -u | awk '/^using System[.;]/ { print; next } { rest = rest $0 "\n" } END { printf "%s", rest }'
    echo ""
    [ -n "$ns" ] && { echo "namespace $ns;"; echo ""; }
    echo "// The maps of $profile, generated by Mapperly at build time (written by mapperly.sh scaffold; the application owns"
    echo "// it). Each map of AutoMapper is quoted above its method: translate its options (the skill automapper), then take"
    echo "// the quote out. The rules of every mapper of the project: MapperDefaults.cs."
    echo "[Mapper]"
    echo "$kind"
    echo "{"
    : > "$tmp/methods"
    while IFS="$(printf '\t')" read -r first last text; do
      t=$(types_of "$text")
      src=$(printf '%s' "$t" | cut -f1) dst=$(printf '%s' "$t" | cut -f2)
      sed -n "${first},${last}p" "$file" | sed -E 's/^[[:space:]]+//; s/^/    \/\/   /; 1s/^    \/\/   /    \/\/ AutoMapper: /'
      if [ "$src" = "?" ] || printf '%s%s' "$src" "$dst" | grep -q '<>'; then
        echo "    // TODO: an open generic or a map of runtime types: a generic method written by hand (the skill automapper)"
        echo ""
        continue
      fi
      # a destination of the language (string, int…): <Source>To<String>
      case "$dst" in
        [a-z]*) method="$(simple_name "$src")To$(printf '%s' "$dst" | cut -c1 | tr '[:lower:]' '[:upper:]')$(printf '%s' "$dst" | cut -c2-)" ;;
        *) method="To$(simple_name "$dst")" ;;
      esac
      while grep -q -x -F "$method $src" "$tmp/methods"; do method="${method}2"; done
      echo "$method $src" >> "$tmp/methods"
      if printf '%s' "$text" | grep -q -E '\.ConvertUsing[<(]'; then
        echo "    // TODO: the conversion above, for every $src of this mapper: [UserMapping(Default = true)] private ${static}$dst $method($src source) => ...;"
        echo ""
        continue
      fi
      echo "    public ${static}partial $dst $method($this$src source);"
      if printf '%s' "$text" | grep -q '\.ReverseMap('; then
        back="To$(simple_name "$src")"
        while grep -q -x -F "$back $dst" "$tmp/methods"; do back="${back}2"; done
        echo "$back $dst" >> "$tmp/methods"
        echo ""
        echo "    // the way back of ReverseMap: its own attributes (an unflattening: [MapProperty(nameof(D.CustomerName), \"Customer.Name\")])"
        echo "    public ${static}partial $src $back($this$dst source);"
      fi
      echo ""
    done < "$tmp/st"
    echo "}"
  } > "$tmp/mapper"
  # no blank line before the closing brace
  awk 'NR > 1 { if (!(prev == "" && $0 == "}")) print prev } { prev = $0 } END { print prev }' "$tmp/mapper" > "$mapper"
  echo "WRITTEN: $mapper"
  sed 's/^/METHOD: /' "$tmp/methods"
  echo "NEXT: translate the options quoted above each method (the skill automapper) and take the quotes out, build (a target member left without source: error RMG012), then the adapter of the snapshot tests and the callers of these maps ($(grep -c . "$tmp/methods") method(s))${services:+; register the mapper in place of AddAutoMapper, with the lifetime of its shortest-lived service}"
  exit 0
fi

# ---------- helpers ----------
if [ "$action" = helpers ]; then
  project=$(from_root "$1")
  [ -n "$project" ] && [ -f "$project" ] || { echo "STOP: mapperly.sh helpers <the test project .csproj>"; exit 1; }
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

// The helpers of the snapshot tests of the maps (written by mapperly.sh helpers, the skill automapper; the tests own
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
// (mapperly.sh record): a golden file that does not exist yet is written; one that exists is never written again.
public static class MappingSnapshot
{
    public static void Verify(object? actual, string name, [CallerFilePath] string caller = "")
    {
        var json = Json(actual);
        var file = Path.Combine(Folder(caller), name + ".json");
        if (!File.Exists(file))
        {
            if (Environment.GetEnvironmentVariable("MAPPING_RECORD") != "1")
                throw new InvalidOperationException($"No golden file {file}: it is recorded on AutoMapper, before the mapper changes (mapperly.sh record)");
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
  echo "HELPERS: $file, namespace $ns: MappingSample.Create<T>(seed, nulls) (a source whose every member has a value of its own; nulls: those that may be null left null), MappingSnapshot.Verify(result, name) (compared with Mapping/Snapshots/<name>.json); then the tests of the maps and the adapter Mapped on AutoMapper (the skill automapper), and mapperly.sh record"
  exit 0
fi

# ---------- record ----------
if [ "$action" = record ]; then
  project=$(from_root "$1") filter=${2:-FullyQualifiedName~Mapping}
  [ -n "$project" ] && [ -f "$project" ] || { echo "STOP: mapperly.sh record <the test project .csproj> [<filter>]"; exit 1; }
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
