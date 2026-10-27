#!/bin/sh
# The replacement of AutoMapper by Mapperly and by Mapster, for real, as /go runs it: the .NET SDKs 10 and 8, the real
# packages (AutoMapper 14.0.0, Riok.Mapperly 4.3.1, Mapster 10.0.13, xUnit, Entity Framework Core with SQLite), the
# pack's scripts and the code of the skills automapper and mapster as they are written. An application whose two
# profiles use every form the skills translate: MapFrom, Ignore, BeforeMap, AfterMap, Condition (on a new object and on
# an existing one: a patch), NullSubstitute, ReverseMap with its unflattening, ProjectTo, a map onto an existing object
# with MemberList.Source, ConvertUsing, Include, ForCtorParam, a resolver that takes a service, a member named in
# another case; a service that maps with IMapper, registered by AddAutoMapper. For each target framework:
#   - the analyst: automapper.sh inventory (the profiles in their order, the maps and their options, the project to set up,
#     the resolver with a service, the calls, the registration, the plan)
#   - before the change (the test-guardian, mission « filet »): automapper.sh helpers, the tests of the skill and those of
#     the invoices, of a projection in SQLite and of the registration, on AutoMapper; automapper.sh record writes their
#     golden files from AutoMapper (never one again, nothing when the tests fail); green twice; sealed with the files
#   - Mapperly: automapper.sh setup (a version the feed does not have: everything put back; then Riok.Mapperly for real,
#     the diagnostics as errors, the rules of the mappers, the build); automapper.sh scaffold translates the profiles
#     (the orders whole: its mapper builds and gives what AutoMapper gave, as it is; the resolver of the invoices left
#     with a TODO line, which the build refuses: RMG012), then the mappers of the skill and its adapter, the sealed tests
#     green twice; the generated code without reflection; what the build refuses (a target member without source RMG012,
#     a source enum member without target RMG038); the last step: AutoMapper removed, check GONE, every test green, no
#     Mapperly assembly in the binaries
#   - Mapster, from the same safety net: automapper.sh setup --mapster (Microsoft.Extensions.DependencyInjection
#     .Abstractions 8: STOP, nothing changed; raised, then Mapster, MapsterSetup.cs and the build), the test of the
#     Registers of the skill, automapper.sh scaffold --mapster (the Register of the orders, the one of the skill, as it
#     is; the resolver left with a TODO line, which the test of the Registers refuses), the Register and the adapter of
#     the skill, the sealed tests green twice; what the test of the Registers refuses (a target member without source);
#     the last step: automapper.sh switch (the service and its registration onto Mapster, IMapper and its calls kept),
#     AutoMapper removed, check GONE, every test green, the registration through the container included
# Needs dotnet (the CI installs the SDKs 10 and 8) and the NuGet feed of the machine (nuget.org in the CI); its own
# package folder; no repository and no setting of this machine is changed. The golden files written by AutoMapper and the
# queries of the projections go to the log. Usage, from opencode-v2/: sh tools/automapper-test.sh [<shell>]
SHELL_UNDER_TEST=${1:-sh}
pack=$(cd "$(dirname "$0")/.." && pwd)
scripts="$pack/scripts"
command -v dotnet >/dev/null 2>&1 || { echo "automapper-test: dotnet is not on the PATH of this machine"; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/automapper-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tmp" "$work/nuget"
TMPDIR="$work/tmp"
NUGET_PACKAGES="$work/nuget"
MSBUILDDISABLENODEREUSE=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 DOTNET_CLI_UI_LANGUAGE=en
export TMPDIR NUGET_PACKAGES MSBUILDDISABLENODEREUSE DOTNET_CLI_TELEMETRY_OPTOUT DOTNET_NOLOGO DOTNET_CLI_UI_LANGUAGE
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$work/gitconfig"
GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
# the pauses of the retries of the scripts (transient.sh): none, a check of a failure that passes by itself does not wait
RETRY_PAUSES="0 0"
export RETRY_PAUSES
printf '[init]\n\tdefaultBranch = develop\n' > "$GIT_CONFIG_GLOBAL"
AUTOMAPPER=14.0.0
MAPPERLY=4.3.1
MAPSTER=10.0.13
echo "automapper-test: SDKs $(dotnet --list-sdks | awk '{ printf "%s%s", sep, $1; sep = ", " }')"

pass=0
fail=0
check() {
  # check <name> <expected exit: 0|1|any> <grep pattern of the output> [<pattern that must not appear>]
  name=$1 want=$2 pattern=$3 absent=$4
  ok=1
  case "$want" in
    any) ;;
    0) [ "$status" -eq 0 ] || ok=0 ;;
    *) [ "$status" -ne 0 ] || ok=0 ;;
  esac
  printf '%s\n' "$out" | grep -qE -- "$pattern" || ok=0
  [ -n "$absent" ] && printf '%s\n' "$out" | grep -qE -- "$absent" && ok=0
  if [ "$ok" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name (exit $status)"
    printf '%s\n' "$out" | sed 's/^/    /' | tail -n 60
  fi
  return "$((1 - ok))"
}
verdict() {
  # verdict <name> <status of the condition>
  if [ "$2" -eq 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi
}
run() {
  script=$1
  shift
  out=$("$SHELL_UNDER_TEST" "$scripts/$script" "$@" 2>&1)
  status=$?
}
commit() { git add -A >/dev/null 2>&1 && git commit -q -m "$1" >/dev/null 2>&1; }
note() { echo "NOTE: $*"; }

# The code blocks of the skill, in order: 1 the adapter of the tests on AutoMapper, 2 the snapshot tests of the maps of
# OrderProfile, 3 the mapper of the orders, 4 the adapter on Mapperly, 5 the mapper of the invoices
blocks="$work/blocks"
mkdir -p "$blocks"
awk -v dir="$blocks" '
  /^ *```[a-z]+$/ { n++; inblock = 1; file = dir "/" n; match($0, /^ */); indent = RLENGTH; next }
  /^ *```$/ && inblock { inblock = 0; close(file); next }
  inblock { line = $0; if (indent > 0 && substr(line, 1, indent) ~ /^ *$/) line = substr(line, indent + 1); print line > file }' "$pack/skills/automapper/SKILL.md"
if [ -s "$blocks/5" ] && [ ! -e "$blocks/6" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: the skill automapper has not its 5 code blocks"; ls "$blocks"; fi
# The code blocks of the skill mapster: m1 the Register of OrderProfile as scaffold writes it, m2 the Register of
# InvoiceProfile finished, m3 the adapter of the tests on Mapster, m4 the test of the Registers
awk -v dir="$blocks" '
  /^ *```[a-z]+$/ { n++; inblock = 1; file = dir "/m" n; match($0, /^ */); indent = RLENGTH; next }
  /^ *```$/ && inblock { inblock = 0; close(file); next }
  inblock { line = $0; if (indent > 0 && substr(line, 1, indent) ~ /^ *$/) line = substr(line, indent + 1); print line > file }' "$pack/skills/mapster/SKILL.md"
if [ -s "$blocks/m4" ] && [ ! -e "$blocks/m5" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: the skill mapster has not its 4 code blocks"; ls "$blocks"; fi

# The application: its domain, its DTOs, its two profiles, a service that maps with IMapper, its registration
application() {
  mkdir -p src/Shop/Mapping src/Shop/Billing tests/Shop.Tests/Mapping
  cat > src/Shop/Shop.csproj <<EOF
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>$tfm</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="AutoMapper" Version="$AUTOMAPPER" />
    <PackageReference Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="8.0.2" />
  </ItemGroup>

</Project>
EOF
  cat > src/Shop/Domain.cs <<'EOF'
namespace Shop.Domain;

public enum OrderStatus { Draft, Paid, Shipped }

public class Address
{
    public string? Street { get; set; }
    public string? City { get; set; }
}

public class Customer
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string? Email { get; set; }
    public Address? Address { get; set; }
}

public class OrderLine
{
    public int Id { get; set; }
    public string Product { get; set; } = "";
    public int Quantity { get; set; }
    public decimal UnitPrice { get; set; }
}

public class Order
{
    public int Id { get; set; }
    public string Number { get; set; } = "";
    public DateTime CreatedAt { get; set; }
    public OrderStatus Status { get; set; }
    public Customer? Customer { get; set; }
    public List<OrderLine>? Lines { get; set; }
    public decimal Discount { get; set; }
    public string? Comment { get; set; }
}
EOF
  cat > src/Shop/Dtos.cs <<'EOF'
using Shop.Domain;

namespace Shop.Dtos;

public enum OrderStatusDto { Draft, Paid, Shipped, Unknown }

public class OrderLineDto
{
    public string Product { get; set; } = "";
    public int Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal Amount { get; set; }
}

public class OrderDto
{
    public int Id { get; set; }
    public string Number { get; set; } = "";
    public string Created { get; set; } = "";
    public OrderStatusDto Status { get; set; }
    public string? CustomerName { get; set; }
    public string? CustomerAddressCity { get; set; }
    public List<OrderLineDto> Lines { get; set; } = null!;
    public int LineCount { get; set; }
    public decimal Total { get; set; }
    public decimal Discount { get; set; }
    public string Comment { get; set; } = "";
    public string? Audit { get; set; }
    public string? Summary { get; set; }
}

public class CustomerDto
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string? Email { get; set; }
    public string? AddressStreet { get; set; }
    public string? AddressCity { get; set; }
}

public class OrderListItemDto
{
    public int Id { get; set; }
    public string Number { get; set; } = "";
    public string? CustomerName { get; set; }
    public OrderStatus Status { get; set; }
    public int LineCount { get; set; }
}

public class OrderLineUpdate
{
    public string Product { get; set; } = "";
    public int Quantity { get; set; }
    public decimal UnitPrice { get; set; }
}

public class OrderUpdate
{
    public string? Comment { get; set; }
    public decimal Discount { get; set; }
    public List<OrderLineUpdate> Lines { get; set; } = new();
}
EOF
  cat > src/Shop/Mapping/OrderProfile.cs <<'EOF'
using System.Globalization;
using AutoMapper;
using Shop.Domain;
using Shop.Dtos;

namespace Shop.Mapping;

public class OrderProfile : Profile
{
    public OrderProfile()
    {
        CreateMap<OrderLine, OrderLineDto>()
            .ForMember(d => d.Amount, o => o.MapFrom(s => s.Quantity * s.UnitPrice));

        CreateMap<Order, OrderDto>()
            .ForMember(d => d.Created, o => o.MapFrom(s => s.CreatedAt.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)))
            .ForMember(d => d.LineCount, o => o.MapFrom(s => s.Lines == null ? 0 : s.Lines.Count))
            .ForMember(d => d.Total, o => o.MapFrom(s => (s.Lines == null ? 0m : s.Lines.Sum(l => l.Quantity * l.UnitPrice)) - s.Discount))
            .ForMember(d => d.Discount, o => o.Condition(s => s.Status == OrderStatus.Paid))
            .ForMember(d => d.Comment, o => o.NullSubstitute("(aucun)"))
            .ForMember(d => d.Audit, o => o.Ignore())
            .ForMember(d => d.Summary, o => o.Ignore())
            .BeforeMap((s, d) => d.Audit = "mappé")
            .AfterMap((s, d) => d.Summary = $"{d.Number} : {d.LineCount} ligne(s)");

        CreateMap<Customer, CustomerDto>().ReverseMap();

        // the list of the orders page, through ProjectTo
        CreateMap<Order, OrderListItemDto>()
            .ForMember(d => d.LineCount, o => o.MapFrom(s => s.Lines!.Count));

        CreateMap<OrderLineUpdate, OrderLine>()
            .ForMember(d => d.Id, o => o.Ignore());
        // a patch: a null comment keeps the comment of the order
        CreateMap<OrderUpdate, Order>(MemberList.Source)
            .ForMember(d => d.Comment, o => o.Condition(s => s.Comment != null));
    }
}
EOF
  cat > src/Shop/Billing/Billing.cs <<'EOF'
namespace Billing;

public readonly record struct Money(decimal Amount, string Currency);

public abstract class Payment
{
    public decimal Amount { get; set; }
}

public class CardPayment : Payment
{
    public string Last4 { get; set; } = "";
}

public class TransferPayment : Payment
{
    public string Iban { get; set; } = "";
}

public class Invoice
{
    public int Id { get; set; }
    public string Reference { get; set; } = "";
    public Money Price { get; set; }
    public string CustomerFirstName { get; set; } = "";
    public string CustomerLastName { get; set; } = "";
    public string Country { get; set; } = "";
    public List<Payment> Payments { get; set; } = new();
}

public abstract class PaymentDto
{
    public decimal Amount { get; set; }
}

public class CardPaymentDto : PaymentDto
{
    public string Last4 { get; set; } = "";
}

public class TransferPaymentDto : PaymentDto
{
    public string Iban { get; set; } = "";
}

public record CustomerSummary(string Label);

public class InvoiceDto
{
    public int Id { get; set; }
    public string REFERENCE { get; set; } = "";
    public string Price { get; set; } = "";
    public CustomerSummary? Customer { get; set; }
    public List<PaymentDto> Payments { get; set; } = new();
    public decimal Tax { get; set; }
}

public interface ITaxRates
{
    decimal RateFor(string country);
}
EOF
  cat > src/Shop/Billing/InvoiceProfile.cs <<'EOF'
using System.Globalization;
using AutoMapper;

namespace Billing;

public class InvoiceProfile : Profile
{
    public InvoiceProfile()
    {
        CreateMap<Money, string>().ConvertUsing(m => m.Amount.ToString("0.00", CultureInfo.InvariantCulture) + " " + m.Currency);
        CreateMap<Payment, PaymentDto>()
            .Include<CardPayment, CardPaymentDto>()
            .Include<TransferPayment, TransferPaymentDto>();
        CreateMap<CardPayment, CardPaymentDto>();
        CreateMap<TransferPayment, TransferPaymentDto>();
        CreateMap<Invoice, CustomerSummary>()
            .ForCtorParam(nameof(CustomerSummary.Label), o => o.MapFrom(s => s.CustomerLastName.ToUpperInvariant() + ", " + s.CustomerFirstName));
        CreateMap<Invoice, InvoiceDto>()
            .ForMember(d => d.Customer, o => o.MapFrom(s => s))
            .ForMember(d => d.Tax, o => o.MapFrom<TaxResolver>());
    }
}

// the tax of an invoice, from the rate of its country (a service)
public class TaxResolver(ITaxRates rates) : IValueResolver<Invoice, InvoiceDto, decimal>
{
    public decimal Resolve(Invoice source, InvoiceDto destination, decimal destMember, ResolutionContext context) =>
        Math.Round(source.Price.Amount * rates.RateFor(source.Country), 2);
}
EOF
  cat > src/Shop/OrderService.cs <<'EOF'
using AutoMapper;
using AutoMapper.QueryableExtensions;
using Shop.Domain;
using Shop.Dtos;

namespace Shop;

public class OrderService(IMapper mapper)
{
    public OrderDto Get(Order order) => mapper.Map<OrderDto>(order);

    public void Update(Order order, OrderUpdate update) => mapper.Map(update, order);

    public IQueryable<OrderListItemDto> List(IQueryable<Order> orders) => orders.ProjectTo<OrderListItemDto>(mapper.ConfigurationProvider);
}
EOF
  cat > src/Shop/ServiceRegistration.cs <<'EOF'
using Microsoft.Extensions.DependencyInjection;
using Shop.Mapping;

namespace Shop;

public static class ServiceRegistration
{
    public static IServiceCollection AddShop(this IServiceCollection services) =>
        services.AddAutoMapper(typeof(OrderProfile)).AddScoped<OrderService>();
}
EOF
  cat > tests/Shop.Tests/Shop.Tests.csproj <<EOF
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>$tfm</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <IsPackable>false</IsPackable>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />
    <PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="$di" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.Sqlite" Version="$ef" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="../../src/Shop/Shop.csproj" />
  </ItemGroup>

</Project>
EOF
  printf 'bin/\nobj/\n' > .gitignore
}

# The tests of this story beyond those of the skill: the invoices (a resolver with a service, through the container of
# AddAutoMapper), the projection in a real database, the service of the orders from the container
more_tests() {
  cat > tests/Shop.Tests/Mapping/InvoiceMappingTests.cs <<'EOF'
using Billing;
using Xunit;

namespace Shop.Tests.Mapping;

public class InvoiceMappingTests
{
    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    public void Invoice_ToInvoiceDto(int seed) =>
        MappingSnapshot.Verify(MappedInvoice.ToInvoiceDto(MappingSample.Create<Invoice>(seed)), $"InvoiceDto.{seed}");
}

public sealed class FixedTaxRates : ITaxRates
{
    public decimal RateFor(string country) => country.EndsWith("-1", StringComparison.Ordinal) ? 0.2m : 0.055m;
}
EOF
  cat > tests/Shop.Tests/Mapping/MappedInvoice.cs <<'EOF'
using AutoMapper;
using Billing;
using Microsoft.Extensions.DependencyInjection;

namespace Shop.Tests.Mapping;

internal static class MappedInvoice
{
    private static readonly IMapper Mapper = new ServiceCollection()
        .AddSingleton<ITaxRates, FixedTaxRates>()
        .AddAutoMapper(typeof(InvoiceProfile))
        .BuildServiceProvider()
        .GetRequiredService<IMapper>();

    public static InvoiceDto ToInvoiceDto(Invoice source) => Mapper.Map<InvoiceDto>(source);
}
EOF
  cat > tests/Shop.Tests/Mapping/SqliteProjectionTests.cs <<'EOF'
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Shop.Domain;
using Xunit;

namespace Shop.Tests.Mapping;

// The projection of the orders list in a real database: the query the map gives, and its rows
public class SqliteProjectionTests
{
    private sealed class ShopDb(DbContextOptions<ShopDb> options) : DbContext(options)
    {
        public DbSet<Order> Orders => Set<Order>();

        protected override void OnModelCreating(ModelBuilder model)
        {
            model.Entity<Customer>().OwnsOne(c => c.Address);
            model.Entity<Order>().HasMany(o => o.Lines).WithOne().HasForeignKey("OrderId");
        }
    }

    [Fact]
    public void Orders_ProjectToOrderListItemDto_InSqlite()
    {
        using var connection = new SqliteConnection("DataSource=:memory:");
        connection.Open();
        var options = new DbContextOptionsBuilder<ShopDb>().UseSqlite(connection).Options;
        using (var db = new ShopDb(options))
        {
            db.Database.EnsureCreated();
            var orders = new[] { MappingSample.Create<Order>(), MappingSample.Create<Order>(seed: 2), MappingSample.Create<Order>(seed: 3, nulls: true) };
            foreach (var line in orders.SelectMany(o => o.Lines ?? new List<OrderLine>()))
            {
                line.Id = 0;
            }

            db.Orders.AddRange(orders);
            db.SaveChanges();
        }

        using (var db = new ShopDb(options))
        {
            var query = Mapped.ProjectToOrderListItemDto(db.Orders.OrderBy(o => o.Id));
            var sql = Environment.GetEnvironmentVariable("MAPPING_SQL");
            if (!string.IsNullOrEmpty(sql))
            {
                File.AppendAllText(sql, query.ToQueryString() + "\n");
            }

            MappingSnapshot.Verify(query.ToList(), "OrderListItemDto.Sqlite");
        }
    }
}
EOF
  cat > tests/Shop.Tests/Mapping/RegistrationTests.cs <<'EOF'
using Billing;
using Microsoft.Extensions.DependencyInjection;
using Shop.Domain;
using Xunit;

namespace Shop.Tests.Mapping;

// The service of the orders, from the container as the application registers it
public class RegistrationTests
{
    [Fact]
    public void OrderService_FromTheContainer()
    {
        using var provider = new ServiceCollection().AddSingleton<ITaxRates, FixedTaxRates>().AddShop().BuildServiceProvider();
        using var scope = provider.CreateScope();
        MappingSnapshot.Verify(scope.ServiceProvider.GetRequiredService<OrderService>().Get(MappingSample.Create<Order>()), "OrderService.Get");
    }
}
EOF
}

# The errors of a build, each once
errors() {
  printf '%s\n' "$out" | grep -E 'error [A-Z]+[0-9]+' | sed -E 's/ \[[^]]*\]$//; s/^.*\/([^/]+\.cs)/\1/' | sort -u | head -n 12
}

scenario() {
  tfm=$1
  case "$tfm" in
    net8.0) ef=8.0.11 di=8.0.1 ;;
    *) ef=10.0.0 di=10.0.0 ;;
  esac
  repo="$work/$tfm"
  mkdir -p "$repo"
  cd "$repo" || return 0
  git init -q
  application
  commit "feat: the shop, mapped by AutoMapper"
  t=tests/Shop.Tests/Shop.Tests.csproj

  run build-test.sh --build-only src/Shop/Shop.csproj
  check "$tfm: the shop builds with AutoMapper $AUTOMAPPER" 0 '^BUILD: OK' || return 0
  audit=$(printf '%s\n' "$out" | grep -o -E 'NU190[1-4][^;]*AutoMapper[^;]*' | head -n 1 | cut -c1-200)
  [ -n "$audit" ] && note "$tfm, NuGet audit on AutoMapper $AUTOMAPPER: $audit"

  # ---- the analyst: what maps with AutoMapper, the plan ----
  run automapper.sh inventory
  check "$tfm: inventory: the files, the maps, the version" 0 "^INVENTORY: 2 file\\(s\\) with maps, 12 map\\(s\\), AutoMapper $AUTOMAPPER\$"
  check "$tfm: inventory: the CVE of the free versions" 0 "^PACKAGE: AutoMapper $AUTOMAPPER: a free version, with CVE-2026-32933"
  check "$tfm: inventory: the two profiles, in their order" 0 '^PROFILE: src/Shop/Billing/InvoiceProfile\.cs — InvoiceProfile — 6 map\(s\), 3 option\(s\) beyond an attribute per member — step 1$'
  check "$tfm: inventory: the second profile" 0 '^PROFILE: src/Shop/Mapping/OrderProfile\.cs — OrderProfile — 6 map\(s\), 4 option\(s\) beyond an attribute per member — step 2$'
  check "$tfm: inventory: a map and its options" 0 '^MAP: src/Shop/Mapping/OrderProfile\.cs:15 Order -> OrderDto — ForMember×7, MapFrom×3, Ignore×2, BeforeMap, AfterMap, Condition, NullSubstitute$'
  check "$tfm: inventory: the project to set up" 0 '^PROJECTS: src/Shop/Shop\.csproj \(Riok\.Mapperly to add'
  check "$tfm: inventory: the resolver that takes a service" 0 '^CONVERTER: src/Shop/Billing/InvoiceProfile\.cs:[0-9]+ TaxResolver \(IValueResolver<Invoice, InvoiceDto, decimal>\) — takes services'
  check "$tfm: inventory: the calls" 0 '^CALL: src/Shop/OrderService\.cs:12 Map\(source, destination\)'
  check "$tfm: inventory: the projection" 0 '^CALL: src/Shop/OrderService\.cs:14 ProjectTo'
  check "$tfm: inventory: the registration" 0 '^REGISTRATION: src/Shop/ServiceRegistration\.cs:9 .*AddAutoMapper'
  check "$tfm: inventory: the plan" 0 "^PLAN: the developer's answer first"

  # ---- before the change: the safety net of the maps (the test-guardian, mission « filet ») ----
  run automapper.sh helpers "$t"
  check "$tfm: helpers: written in the test project, its namespace" 0 '^HELPERS: tests/Shop\.Tests/Mapping/MappingSnapshot\.cs, namespace Shop\.Tests\.Mapping: ' || return 0
  cp "$blocks/1" tests/Shop.Tests/Mapping/Mapped.cs
  cp "$blocks/2" tests/Shop.Tests/Mapping/OrderMappingTests.cs
  more_tests
  run build-test.sh "$t" --filter FullyQualifiedName~Mapping
  check "$tfm: without golden files, the tests say how to record them" 1 'No golden file .*automapper\.sh record'
  run automapper.sh record "$t"
  if ! check "$tfm: record: the golden files written from AutoMapper" 0 '^RECORD: 14 golden file\(s\) written from AutoMapper'; then
    return 0
  fi
  # what AutoMapper gave, for the log (the contract Mapperly meets below)
  [ "$tfm" = net10.0 ] && for f in tests/Shop.Tests/Mapping/Snapshots/*.json; do
    echo "GOLDEN $(basename "$f"): $(tr -d '\n' < "$f" | tr -s ' ')"
  done | tee -a "${AUTOMAPPER_TEST_SHOW:-/dev/null}"
  run automapper.sh record "$t"
  check "$tfm: record again: no golden file written again" 0 '^RECORD: 0 golden file\(s\)'
  MAPPING_SQL="$work/sql-$tfm-automapper.txt"
  export MAPPING_SQL
  run test-guardian.sh green "$t" FullyQualifiedName~Mapping
  unset MAPPING_SQL
  check "$tfm: the snapshot tests on AutoMapper: green twice" 0 '^GREEN: 14 tests pass, twice$' || return 0
  note "$tfm, the projection of AutoMapper in SQLite: $(head -n 12 "$work/sql-$tfm-automapper.txt" 2>/dev/null | tr '\n' ' ' | tr -s ' ' | cut -c1-400)"
  run test-guardian.sh tests-only
  check "$tfm: only the test project changed" 0 '^TESTS-ONLY: OK'
  # sealed: the tests and their golden files, never the adapters (the coder switches them to the mappers)
  run test-guardian.sh seal F1 tests/Shop.Tests/Mapping/MappingSnapshot.cs tests/Shop.Tests/Mapping/OrderMappingTests.cs \
    tests/Shop.Tests/Mapping/InvoiceMappingTests.cs tests/Shop.Tests/Mapping/SqliteProjectionTests.cs \
    tests/Shop.Tests/Mapping/RegistrationTests.cs tests/Shop.Tests/Mapping/Snapshots/*.json
  check "$tfm: the tests and their golden files sealed" 0 '^SEALED: 19 test files'
  commit "test: the snapshot tests of the maps, recorded on AutoMapper"
  # a golden file edited: the contract is the committed one, record refuses
  golden=tests/Shop.Tests/Mapping/Snapshots/OrderDto.Paid.json
  sed -i 's/"Comment": "Comment-1"/"Comment": "autre"/' "$golden"
  run automapper.sh record "$t"
  check "$tfm: record with a golden file edited: STOP, nothing run" 1 '^STOP: golden files committed and changed since \(tests/Shop\.Tests/Mapping/Snapshots/OrderDto\.Paid\.json\)'
  # a golden file committed that no longer matches what AutoMapper gives: record writes nothing, and says where
  commit "test: a golden file that no longer matches"
  run automapper.sh record "$t"
  check "$tfm: record with a golden file that no longer matches: nothing recorded" 1 '^STOP: the snapshot tests do not pass on AutoMapper: nothing recorded$'
  check "$tfm: record says which line differs" 1 'expected: "Comment": "autre"'
  git reset -q --hard HEAD~1
  [ -z "$(git status --porcelain)" ] && grep -q '"Comment": "Comment-1"' "$golden"
  verdict "$tfm: record left nothing behind ($(git status --porcelain | head -n 3 | tr '\n' ' '))" $?
  # the same repository, its safety net sealed, for the story of Mapster (below)
  cp -R "$repo" "$work/$tfm-mapster" && rm -rf "$work/$tfm-mapster"/src/Shop/bin "$work/$tfm-mapster"/src/Shop/obj \
    "$work/$tfm-mapster"/tests/Shop.Tests/bin "$work/$tfm-mapster"/tests/Shop.Tests/obj

  # ---- the pilot, once the developer agreed: Mapperly in the project ----
  mkdir -p "$NUGET_PACKAGES/riok.mapperly/99.0.0"
  run automapper.sh setup src/Shop
  check "$tfm: setup with a version the feed does not have: STOP" 1 '^STOP: the build of src/Shop/Shop\.csproj fails with Riok\.Mapperly 99\.0\.0: every file put back, nothing changed$'
  rm -rf "$NUGET_PACKAGES/riok.mapperly/99.0.0"
  [ -z "$(git status --porcelain)" ]
  verdict "$tfm: setup that fails: every file as it was ($(git status --porcelain | head -n 3 | tr '\n' ' '))" $?
  run automapper.sh setup src/Shop
  check "$tfm: setup: Mapperly, compile time only, its rules, the build" 0 "^SETUP: Riok\\.Mapperly $MAPPERLY added to src/Shop/Shop\\.csproj, compile time only .*build OK\$" || return 0
  grep -q "<PackageReference Include=\"Riok.Mapperly\" Version=\"$MAPPERLY\" ExcludeAssets=\"runtime\" PrivateAssets=\"all\" />" src/Shop/Shop.csproj &&
    grep -q '<GlobalAnalyzerConfigFiles Include="Mapperly.globalconfig" />' src/Shop/Shop.csproj &&
    grep -q '^dotnet_diagnostic.RMG012.severity = error$' src/Shop/Mapperly.globalconfig &&
    grep -q 'RequiredEnumMappingStrategy = RequiredMappingStrategy.Source' src/Shop/MapperDefaults.cs
  verdict "$tfm: setup: the PackageReference, the diagnostics as errors, the rules of the mappers" $?
  run automapper.sh setup src/Shop
  check "$tfm: setup again: nothing added" 0 '^SETUP: Riok\.Mapperly already in src/Shop/Shop\.csproj; .*, kept as they were; build OK$'
  commit "build: add Mapperly"

  # ---- the coder: the mappers ----
  run automapper.sh scaffold src/Shop/Mapping/OrderProfile.cs
  check "$tfm: scaffold: the mapper of the orders" 0 '^WRITTEN: src/Shop/Mapping/OrderMapper\.cs$'
  check "$tfm: scaffold: a method per map, and the way back of ReverseMap" 0 '^METHOD: ToCustomer CustomerDto$'
  check "$tfm: scaffold: every map of the orders translated" 0 '^NEXT: 0 TODO line\(s\)'
  run automapper.sh scaffold src/Shop/Mapping/OrderProfile.cs
  check "$tfm: scaffold again: the mapper kept" 0 '^KEPT: src/Shop/Mapping/OrderMapper\.cs '
  run automapper.sh scaffold src/Shop/Billing/InvoiceProfile.cs
  check "$tfm: scaffold: an instance mapper, the service of its resolver in its constructor" 0 '; an instance mapper: its resolvers take ITaxRates rates$'
  check "$tfm: scaffold: the resolver left to finish" 0 '^NEXT: 1 TODO line\(s\)'
  grep -q '^public partial class InvoiceMapper(ITaxRates rates)$' src/Shop/Billing/InvoiceMapper.cs
  verdict "$tfm: scaffold: public partial class InvoiceMapper(ITaxRates rates)" $?
  run build-test.sh --build-only src/Shop/Shop.csproj
  check "$tfm: the build refuses the member left to finish (RMG012 on Tax), nothing in the mapper of the orders" 1 'error RMG012: .*Tax.*InvoiceDto' 'OrderMapper\.cs\([0-9,]+\): error'
  note "$tfm, the mappers as scaffold wrote them: $(errors | cut -c1-150 | head -n 4 | tr '\n' ' ')"
  # the TODO line finished as the skill does it; the adapters of the tests on Mapperly
  cp "$blocks/5" src/Shop/Billing/InvoiceMapper.cs
  cp "$blocks/4" tests/Shop.Tests/Mapping/Mapped.cs
  cat > tests/Shop.Tests/Mapping/MappedInvoice.cs <<'EOF'
using Billing;

namespace Shop.Tests.Mapping;

internal static class MappedInvoice
{
    private static readonly InvoiceMapper Mapper = new(new FixedTaxRates());

    public static InvoiceDto ToInvoiceDto(Invoice source) => Mapper.ToInvoiceDto(source);
}
EOF
  run build-test.sh --build-only src/Shop/Shop.csproj
  if ! check "$tfm: the mapper of the orders as scaffold wrote it builds, every member mapped" 0 '^BUILD: OK'; then
    return 0
  fi
  run test-guardian.sh sealed F1
  check "$tfm: the sealed tests and golden files, unchanged" 0 '^SEAL: OK'
  run test-guardian.sh green "$t" FullyQualifiedName~Mapping
  check "$tfm: the mapper scaffold wrote: what AutoMapper gave, member by member, green twice" 0 '^GREEN: 14 tests pass, twice$'
  # the mapper of the orders of the skill, written by hand from it: the same
  cp "$blocks/3" src/Shop/Mapping/OrderMapper.cs
  run build-test.sh --build-only src/Shop/Shop.csproj
  if ! check "$tfm: the mappers of the skill build, every member mapped" 0 '^BUILD: OK'; then
    return 0
  fi
  MAPPING_SQL="$work/sql-$tfm-mapperly.txt"
  export MAPPING_SQL
  run test-guardian.sh green "$t" FullyQualifiedName~Mapping
  unset MAPPING_SQL
  check "$tfm: the same tests on the mappers of the skill: what AutoMapper gave, member by member, green twice" 0 '^GREEN: 14 tests pass, twice$'
  note "$tfm, the projection of Mapperly in SQLite: $(head -n 12 "$work/sql-$tfm-mapperly.txt" 2>/dev/null | tr '\n' ' ' | tr -s ' ' | cut -c1-400)"
  # the generated code: plain C#, no reflection
  gen="$work/generated-$tfm"
  dotnet build src/Shop/Shop.csproj --no-incremental -nologo -v q -p:EmitCompilerGeneratedFiles=true -p:CompilerGeneratedFilesOutputPath="$gen" > "$work/gen-$tfm.log" 2>&1
  files=$(find "$gen" -name '*Mapper*.g.cs' 2>/dev/null | sort)
  [ -n "$files" ] && ! printf '%s\n' "$files" | xargs grep -l -E 'System\.Reflection|Activator\.|GetType\(\)\.GetPropert|Expression\.Lambda' > /dev/null 2>&1
  verdict "$tfm: the generated code, without reflection ($(printf '%s\n' "$files" | sed 's/.*\///' | tr '\n' ' '))" $?
  if [ "$tfm" = net10.0 ]; then
    for f in $files; do
      echo "GENERATED $(basename "$f"):"
      sed 's/^/    /' "$f"
    done | tee -a "${AUTOMAPPER_TEST_SHOW:-/dev/null}"
  fi
  [ -n "$files" ] || tail -n 5 "$work/gen-$tfm.log" | sed 's/^/    /'
  commit "refactor: the maps of the orders and of the invoices by Mapperly"

  # ---- what the build refuses now ----
  sed -i 's/^    public string? Summary { get; set; }$/&\n    public string? Note { get; set; }/' src/Shop/Dtos.cs
  run build-test.sh --build-only src/Shop/Shop.csproj
  check "$tfm: a target member added without source: the build fails (RMG012)" 1 'error RMG012: .*Note.*OrderDto'
  git checkout -q -- src/Shop/Dtos.cs
  sed -i 's/^public enum OrderStatus { Draft, Paid, Shipped }$/public enum OrderStatus { Draft, Paid, Shipped, Cancelled }/' src/Shop/Domain.cs
  run build-test.sh --build-only src/Shop/Shop.csproj
  check "$tfm: a source enum member without target: the build fails (RMG038)" 1 'error RMG038: .*Cancelled'
  git checkout -q -- src/Shop/Domain.cs

  # ---- the last step: AutoMapper leaves ----
  run automapper.sh check
  check "$tfm: check before the last step: what is left, exit 1" 1 '^AUTOMAPPER: [0-9]+ place\(s\) left$'
  check "$tfm: check before the last step: the service, the registration, the package" 1 '^LEFT: project: src/Shop/Shop\.csproj:[0-9]+:.*AutoMapper' 'LEFT: .*(OrderMapper|InvoiceMapper)\.cs'
  rm -f src/Shop/Mapping/OrderProfile.cs src/Shop/Billing/InvoiceProfile.cs
  sed -i '/Include="AutoMapper"/d' src/Shop/Shop.csproj
  cat > src/Shop/OrderService.cs <<'EOF'
using Shop.Domain;
using Shop.Dtos;
using Shop.Mapping;

namespace Shop;

public class OrderService
{
    public OrderDto Get(Order order) => order.ToOrderDto();

    public void Update(Order order, OrderUpdate update) => update.ApplyTo(order);

    public IQueryable<OrderListItemDto> List(IQueryable<Order> orders) => orders.ProjectToOrderListItemDto();
}
EOF
  cat > src/Shop/ServiceRegistration.cs <<'EOF'
using Billing;
using Microsoft.Extensions.DependencyInjection;

namespace Shop;

public static class ServiceRegistration
{
    public static IServiceCollection AddShop(this IServiceCollection services) =>
        services.AddScoped<InvoiceMapper>().AddScoped<OrderService>();
}
EOF
  run automapper.sh check
  check "$tfm: check: GONE" 0 '^AUTOMAPPER: GONE ' '^LEFT: '
  run build-test.sh "$t"
  check "$tfm: without AutoMapper, the build and every test green" 0 '^TESTS: OK' 'FAILED TESTS'
  run test-guardian.sh sealed F1
  check "$tfm: the tests and golden files still as sealed" 0 '^SEAL: OK'
  left=$(find src/Shop/bin tests/Shop.Tests/bin -name 'Riok.Mapperly*.dll' 2>/dev/null)
  [ -z "$left" ]
  verdict "$tfm: no assembly of Mapperly in the binaries${left:+ ($left)}" $?
  commit "chore: remove AutoMapper"
}

# The same application, from its safety net sealed on AutoMapper, onto Mapster
mapster() {
  tfm=$1
  repo="$work/$tfm-mapster"
  [ -d "$repo" ] || { fail=$((fail + 1)); echo "FAIL: $tfm, Mapster: no repository with the safety net (the story of Mapperly stopped before it)"; return 0; }
  cd "$repo" || return 0
  t=tests/Shop.Tests/Shop.Tests.csproj

  # ---- the pilot, once the developer answered « Cible : Mapster » ----
  run automapper.sh setup --mapster src/Shop
  check "$tfm, Mapster: setup with Microsoft.Extensions.DependencyInjection.Abstractions 8: STOP" 1 '^STOP: Mapster\.DependencyInjection [0-9.]+ needs Microsoft\.Extensions\.DependencyInjection\.Abstractions 9\.0\.0 or more .*src/Shop/Shop\.csproj:[0-9]+'
  [ -z "$(git status --porcelain)" ]
  verdict "$tfm, Mapster: setup that stops: nothing changed ($(git status --porcelain | head -n 3 | tr '\n' ' '))" $?
  sed -i 's/Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="8.0.2"/Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="9.0.0"/' src/Shop/Shop.csproj
  commit "build: Microsoft.Extensions.DependencyInjection.Abstractions 9.0.0"
  run automapper.sh setup --mapster src/Shop
  check "$tfm, Mapster: setup: the packages, MapsterSetup.cs, the build" 0 "^SETUP: Mapster $MAPSTER and Mapster\\.DependencyInjection $MAPSTER added to src/Shop/Shop\\.csproj; src/Shop/MapsterSetup\\.cs written .*; build OK\$" || return 0
  grep -q 'AddDestinationTransform(DestinationTransform.EmptyCollectionIfNull);' src/Shop/MapsterSetup.cs &&
    grep -q '^namespace Shop;$' src/Shop/MapsterSetup.cs
  verdict "$tfm, Mapster: MapsterSetup.cs, the rules of AutoMapper, in the root namespace" $?
  run automapper.sh setup --mapster src/Shop
  check "$tfm, Mapster: setup again: nothing added" 0 '^SETUP: Mapster already in src/Shop/Shop\.csproj; src/Shop/MapsterSetup\.cs kept; build OK$'
  commit "build: add Mapster"

  # ---- the test-guardian, with the first profile: the test of the Registers ----
  cp "$blocks/m4" tests/Shop.Tests/Mapping/MapsterConfigurationTests.cs
  run build-test.sh "$t" --filter FullyQualifiedName~MapsterConfigurationTests
  check "$tfm, Mapster: the test of the Registers, green before any Register" 0 '^TESTS: OK' || return 0
  run test-guardian.sh seal F2 tests/Shop.Tests/Mapping/MapsterConfigurationTests.cs
  check "$tfm, Mapster: the test of the Registers sealed" 0 '^SEALED: 1 test files'
  commit "test: the test of the Registers of Mapster"

  # ---- the coder: the Registers ----
  run automapper.sh scaffold --mapster src/Shop/Mapping/OrderProfile.cs
  check "$tfm, Mapster: scaffold: the Register of the orders, every map translated" 0 '^NEXT: 0 TODO line\(s\)'
  cmp -s "$blocks/m1" src/Shop/Mapping/OrderRegister.cs
  verdict "$tfm, Mapster: scaffold writes the Register of the skill, as it is" $?
  run automapper.sh scaffold --mapster src/Shop/Mapping/OrderProfile.cs
  check "$tfm, Mapster: scaffold again: the Register kept" 0 '^KEPT: src/Shop/Mapping/OrderRegister\.cs '
  run automapper.sh scaffold --mapster src/Shop/Billing/InvoiceProfile.cs
  check "$tfm, Mapster: scaffold: the resolver of the invoices left to finish" 0 '^NEXT: 1 TODO line\(s\)'
  run build-test.sh "$t" --filter FullyQualifiedName~MapsterConfigurationTests
  check "$tfm, Mapster: the test of the Registers refuses the member left to finish (Tax)" 1 'InvoiceDto do not have a corresponding source member mapped or ignored:Tax'
  # the TODO line finished as the skill does it; the adapters of the tests on Mapster
  cp "$blocks/m2" src/Shop/Billing/InvoiceRegister.cs
  cp "$blocks/m3" tests/Shop.Tests/Mapping/Mapped.cs
  cat > tests/Shop.Tests/Mapping/MappedInvoice.cs <<'EOF'
using Billing;
using MapsterMapper;
using Microsoft.Extensions.DependencyInjection;

namespace Shop.Tests.Mapping;

// The maps of the invoices through Mapster as the application registers it (its resolver takes a service)
internal static class MappedInvoice
{
    private static readonly IMapper Mapper = new ServiceCollection()
        .AddSingleton<ITaxRates, FixedTaxRates>()
        .AddMapsterMaps(typeof(InvoiceRegister))
        .BuildServiceProvider()
        .GetRequiredService<IMapper>();

    public static InvoiceDto ToInvoiceDto(Invoice source) => Mapper.Map<InvoiceDto>(source);
}
EOF
  run build-test.sh --build-only src/Shop/Shop.csproj
  check "$tfm, Mapster: the Registers build" 0 '^BUILD: OK' || return 0
  run test-guardian.sh sealed F1
  check "$tfm, Mapster: the sealed tests and golden files, unchanged" 0 '^SEAL: OK'
  MAPPING_SQL="$work/sql-$tfm-mapster.txt"
  export MAPPING_SQL
  run test-guardian.sh green "$t" FullyQualifiedName~Mapping
  unset MAPPING_SQL
  check "$tfm, Mapster: the same tests on Mapster: what AutoMapper gave, member by member, the test of the Registers too, green twice" 0 '^GREEN: 15 tests pass, twice$'
  note "$tfm, the projection of Mapster in SQLite: $(head -n 12 "$work/sql-$tfm-mapster.txt" 2>/dev/null | tr '\n' ' ' | tr -s ' ' | cut -c1-400)"
  commit "refactor: the maps of the orders and of the invoices by Mapster"

  # ---- what the test of the Registers refuses now ----
  sed -i 's/^    public string? Summary { get; set; }$/&\n    public string? Note { get; set; }/' src/Shop/Dtos.cs
  run build-test.sh "$t" --filter FullyQualifiedName~MapsterConfigurationTests
  check "$tfm, Mapster: a target member added without source: the test of the Registers fails" 1 'OrderDto do not have a corresponding source member mapped or ignored:Note'
  git checkout -q -- src/Shop/Dtos.cs

  # ---- the last step: switch, then AutoMapper leaves ----
  run automapper.sh switch
  check "$tfm, Mapster: switch: the service onto Mapster" 0 '^SWITCHED: src/Shop/OrderService\.cs — 3 line\(s\)$'
  check "$tfm, Mapster: switch: its registration" 0 '^SWITCHED: src/Shop/ServiceRegistration\.cs — 1 line\(s\)$'
  check "$tfm, Mapster: switch: nothing left by hand, the profiles left out" 0 '^SWITCH: 2 file\(s\) rewritten .*, 0 line\(s\) left by hand .*, 2 profile or resolver file\(s\) left out' '^LEFT: '
  grep -q 'orders.ProjectToType<OrderListItemDto>(mapper.Config)' src/Shop/OrderService.cs &&
    grep -q '^using MapsterMapper;$' src/Shop/OrderService.cs && grep -q 'mapper.Map(update, order)' src/Shop/OrderService.cs &&
    grep -q 'services.AddMapsterMaps(typeof(OrderRegister)).AddScoped<OrderService>()' src/Shop/ServiceRegistration.cs
  verdict "$tfm, Mapster: switch: ProjectToType, AddMapsterMaps, the calls of IMapper kept" $?
  [ "$tfm" = net10.0 ] && git diff -- src | sed 's/^/    /' | tee -a "${AUTOMAPPER_TEST_SHOW:-/dev/null}"
  run automapper.sh switch
  check "$tfm, Mapster: switch again: nothing to rewrite" 0 '^SWITCH: 0 file\(s\) rewritten'
  rm -f src/Shop/Mapping/OrderProfile.cs src/Shop/Billing/InvoiceProfile.cs
  sed -i '/Include="AutoMapper"/d' src/Shop/Shop.csproj
  run automapper.sh check
  check "$tfm, Mapster: check: GONE" 0 '^AUTOMAPPER: GONE ' '^LEFT: '
  run build-test.sh "$t"
  check "$tfm, Mapster: without AutoMapper, the build and every test green (the registration through the container too)" 0 '^TESTS: OK' 'FAILED TESTS'
  run test-guardian.sh sealed F1
  check "$tfm, Mapster: the tests and golden files still as sealed" 0 '^SEAL: OK'
  run test-guardian.sh sealed F2
  check "$tfm, Mapster: the test of the Registers still as sealed" 0 '^SEAL: OK'
  commit "chore: remove AutoMapper"
}

scenario net10.0
cd "$work" || exit 1
mapster net10.0
cd "$work" || exit 1
if dotnet --list-sdks | grep -q '^8\.'; then
  scenario net8.0
  cd "$work" || exit 1
  mapster net8.0
else
  note "no .NET 8 SDK here: the net8.0 story is not tried"
fi

echo "automapper-test ($SHELL_UNDER_TEST): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
