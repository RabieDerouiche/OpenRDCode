---
name: automapper
description: AutoMapper in a .NET application and its replacement (AutoMapper 15+ is paid, every free version has CVE-2026-32933) - the choice of the target (Mapperly recommended, Mapster the closest, by hand) and the facts that decide it, the snapshot tests recorded on AutoMapper, profile by profile; the Mapperly target in full (each form and its equivalent - ForMember, MapFrom, Ignore, ReverseMap, BeforeMap, AfterMap, Condition, NullSubstitute, ConvertUsing, resolvers with services, Include, ForCtorParam, ProjectTo, a map onto an existing object, IMapper and AddAutoMapper); the inventory, the setup, the translation of each profile and the check done by automapper.sh. Load before writing, fixing, reviewing, testing or removing code that uses AutoMapper or Mapperly; with the skill mapster when the target is Mapster.
compatibility: opencode
---
# AutoMapper → Mapperly or Mapster

AutoMapper is paid from 15.0 (July 2025: a commercial license; the free Community edition only under 5 M USD of yearly revenue, with a license key; `package-licenses.sh`), and every free version (14 and before) carries CVE-2026-32933 (high: a deep object graph overflows the stack, a denial of service), fixed only in the paid 15.1.1 and 16.1.1. Staying on 14 keeps a known flaw, upgrading means paying: never add AutoMapper, never raise its version; its removal is a ticket of its own.

## The target: the developer's answer (« Cible »)
- **Mapperly** (`Riok.Mapperly`, Apache-2.0), recommended: a source generator, the mapping is plain C# written at build time (`<EmitCompilerGeneratedFiles>true</EmitCompilerGeneratedFiles>` shows it under `obj/`), no package at run time, no reflection, the fastest, safe with trimming and Native AOT; what AutoMapper found at run time, if a test called `AssertConfigurationIsValid`, fails the build: a target member without source, an enum member without counterpart. What it costs: each caller of `IMapper` rewritten (`order.ToOrderDto()`), each test that mocks `IMapper` rewritten with the real mapper, the code of BeforeMap, AfterMap and Condition in a method around the generated one (written by `automapper.sh scaffold`), `opts.Items` and the runtime type forms redesigned. This skill.
- **Mapster** (`Mapster`, MIT), the closest to AutoMapper: the same model (a configuration run at start-up, each map compiled on its first use), `IMapper` with the same methods: the calls, the constructors and the tests that mock `IMapper` stay, only their `using` changes (`automapper.sh switch`, the last step); BeforeMap, AfterMap, Condition, resolvers with services and `Items` have their equivalent one for one. What it costs: a member forgotten is found by a test (the test of the Registers), never by the build; the package runs with the application; no Native AOT. The skill `mapster`.
- **By hand** (« Non » to both packages): the methods Mapperly would generate, written by hand, under the same snapshot tests; nothing says that a member added later is not mapped.
The facts of the choice are the two TARGET lines of `automapper.sh inventory`: the calls of `IMapper` and `ProjectTo` to rewrite (Mapperly) or keep (Mapster), the test doubles of `IMapper`, the BeforeMap, AfterMap and Condition, the resolvers with services, `Items` and the mapper used inside a map. Many callers and test doubles of `IMapper`, `Items` or `ResolutionContext` in the maps: Mapster changes the least code; a library, trimming or Native AOT, or the build as the guard: Mapperly. Either way the snapshot tests recorded on AutoMapper decide that nothing changed.

## How the pack runs it
`/go sans ticket : remplacer AutoMapper dans <the profiles, or toute l'application>` (« par Mapperly », « par Mapster » settles the question), or a ticket:
- the analyst: `sh ~/.config/opencode/scripts/automapper.sh inventory` (one call; never the maps counted by hand). Its PROJECTS line goes to « Décisions » as « AutoMapper à remplacer : <the projects of the line> » (the developer is asked the target when /go starts; its TARGET lines, shortened, go with it). Its PROFILE lines are the order of the plan: one step per profile (« step <n> »), each step ending « (filet d'abord) (s'appuyer sur le skill automapper) »; Mapperly: its callers (the CALL lines that map its types) in the same step. After them, one step that removes AutoMapper: Mapster, `automapper.sh switch` first; its packages, the profiles, resolvers and converters, `AddAutoMapper`, the last `IMapper` (Mapperly), its own tests (`AssertConfigurationIsValid`). Its GLOBAL lines go to « Points d'attention » (a setting that changes every map: its equivalent below, or in the skill mapster), its CONVERTER lines that take services to the step of their profile.
- the pilot, when /go starts: the question « Cible », then `sh ~/.config/opencode/scripts/automapper.sh setup <each project>` (Mapster: `setup --mapster`) and its commit.
- the test-guardian, before each profile (mission « filet »): `sh ~/.config/opencode/scripts/automapper.sh helpers <the test project>` once, the adapter on AutoMapper and the snapshot tests of the maps of the profile, their golden files written by `sh ~/.config/opencode/scripts/automapper.sh record <the test project>`, green twice, sealed with their golden files, never `Mapped.cs` (below); Mapster: the test of the Registers with the first profile (the skill mapster). Mapperly: a test that mocks `IMapper`, in the step of its class, rewritten with the real mapping.
- the coder, each profile: `sh ~/.config/opencode/scripts/automapper.sh scaffold <the profile file>` (Mapster: `scaffold --mapster`) translates each map next to the profile; what it does not translate whole is quoted above its code with a TODO line, to finish with the forms below; then the adapter of the tests (`Mapped.cs`: the only test file that changes), the callers (Mapperly). The step is done when the build passes (Mapperly: the mapper complete, it says so; Mapster: and the test of the Registers) and the sealed tests pass as they are, twice. The profiles stay until the last step, which ends when `sh ~/.config/opencode/scripts/automapper.sh check` says « AUTOMAPPER: GONE », the build and every test green.
- the checker: on the last step, `automapper.sh check` (a LEFT line is a « majeur » point); on any step, a TODO line of scaffold left, a test file changed other than `Mapped.cs`, a golden file, `Mapperly.globalconfig`, `MapperDefaults.cs` or `MapsterSetup.cs` changed, is « bloquant ».

`automapper.sh setup` puts in the project: `Riok.Mapperly` with `ExcludeAssets="runtime" PrivateAssets="all"` (compile time only; its version in `Directory.Packages.props` when versions are central); `Mapperly.globalconfig`, the diagnostics of a mapping left incomplete or ambiguous as errors (a target member without source RMG012, a source enum member without target RMG038, an ignore that names nothing RMG004/RMG021, a member ignored and mapped RMG049/RMG050, two methods for the same types without a default RMG060, a projection helper that cannot be inlined RMG068…); `MapperDefaults.cs`, the rules of every mapper as AutoMapper mapped: member names without case, flattening, enums by name ignoring case, and helper methods used only where an attribute names them (`Use = nameof(...)`), or for every pair of their types when marked `[UserMapping(Default = true)]`; C# 9 at least. Never change these two files to make a build pass: the error is the mapping to finish.

## The safety net of a profile: snapshot tests recorded on AutoMapper
One test per map (each way of a ReverseMap; a map used only inside another, as `OrderLine` in `Order`, through the one that contains it), each with a source whose every member has a value of its own (`MappingSample.Create<T>()`) and a source whose members that may be null are null (`nulls: true`); a condition of the profile, both ways; a map onto an existing object (`Map(source, destination)`): the object after it; a `ProjectTo`: the projection over objects (`AsQueryable()`). `MappingSnapshot.Verify` writes what a map gives, member by member with its type, and compares it with its golden file, `Mapping/Snapshots/<name>.json` of the test project: written once from AutoMapper by `automapper.sh record <the test project>` (a test without golden file fails otherwise), committed and sealed with the tests, never edited, never recorded again: a difference is a regression of the mapper. The tests call the maps through `Mapped`, the adapter: on AutoMapper first, then each line calls the generated method (the only test file that changes). `sh ~/.config/opencode/scripts/automapper.sh helpers <the test project>` writes these two helpers once, in `Mapping/MappingSnapshot.cs` of the test project (its namespace, `<the test project>.Mapping`; the tests own it, never changed).
The adapter on AutoMapper, configured as the application configures it (the options of its `AddAutoMapper`, its profiles); a profile whose resolvers take services: `new ServiceCollection().AddSingleton<ITaxRates>(new FixedRates()).AddAutoMapper(typeof(InvoiceProfile)).BuildServiceProvider().GetRequiredService<IMapper>()`, the services given test values:
```csharp
using System.Linq;
using AutoMapper;
using AutoMapper.QueryableExtensions;
using Shop.Domain;
using Shop.Dtos;
using Shop.Mapping;

namespace Shop.Tests.Mapping;

// The maps under test, through AutoMapper as the application configures it. The only test file that changes with the
// mapper: in the step of the profile, each line calls the generated method instead.
internal static class Mapped
{
    private static readonly MapperConfiguration Configuration = new(cfg => cfg.AddProfile<OrderProfile>());
    private static readonly IMapper Mapper = Configuration.CreateMapper();

    public static OrderDto ToOrderDto(Order source) => Mapper.Map<OrderDto>(source);

    public static CustomerDto ToCustomerDto(Customer source) => Mapper.Map<CustomerDto>(source);

    public static Customer ToCustomer(CustomerDto source) => Mapper.Map<Customer>(source);

    public static void ApplyTo(OrderUpdate source, Order target) => Mapper.Map(source, target);

    public static IQueryable<OrderListItemDto> ProjectToOrderListItemDto(IQueryable<Order> source) =>
        source.ProjectTo<OrderListItemDto>(Configuration);
}
```
The tests of the maps of `OrderProfile` (xUnit; MSTest: `[TestMethod]`, `[DataRow]`):
```csharp
using System.Linq;
using Shop.Domain;
using Shop.Dtos;
using Xunit;

namespace Shop.Tests.Mapping;

// What each map of OrderProfile gives, for a source whose every member has a value and for one whose members that may
// be null are null; recorded on AutoMapper, unchanged when the generated mapper replaces it (only Mapped.cs changes)
public class OrderMappingTests
{
    [Theory]
    [InlineData(OrderStatus.Draft)]
    [InlineData(OrderStatus.Paid)]
    public void Order_ToOrderDto(OrderStatus status)
    {
        var order = MappingSample.Create<Order>();
        order.Status = status; // the condition of Discount, both ways
        MappingSnapshot.Verify(Mapped.ToOrderDto(order), $"OrderDto.{status}");
    }

    [Fact]
    public void Order_ToOrderDto_NullMembers() =>
        MappingSnapshot.Verify(Mapped.ToOrderDto(MappingSample.Create<Order>(nulls: true)), "OrderDto.Nulls");

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void Customer_ToCustomerDto(bool nulls) =>
        MappingSnapshot.Verify(Mapped.ToCustomerDto(MappingSample.Create<Customer>(nulls: nulls)), nulls ? "CustomerDto.Nulls" : "CustomerDto");

    // the way back of ReverseMap
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void CustomerDto_ToCustomer(bool nulls) =>
        MappingSnapshot.Verify(Mapped.ToCustomer(MappingSample.Create<CustomerDto>(nulls: nulls)), nulls ? "Customer.Nulls" : "Customer");

    // Map(update, order): onto an existing order; nulls: the condition of Comment the other way (the comment kept)
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void OrderUpdate_ApplyTo(bool nulls)
    {
        var order = MappingSample.Create<Order>();
        Mapped.ApplyTo(MappingSample.Create<OrderUpdate>(seed: 2, nulls: nulls), order);
        MappingSnapshot.Verify(order, nulls ? "Order.Updated.Nulls" : "Order.Updated");
    }

    // ProjectTo: the projection over objects (a database runs the same expression)
    [Fact]
    public void Orders_ProjectToOrderListItemDto()
    {
        var orders = new[] { MappingSample.Create<Order>(), MappingSample.Create<Order>(seed: 2) }.AsQueryable();
        MappingSnapshot.Verify(Mapped.ProjectToOrderListItemDto(orders).ToList(), "OrderListItemDto");
    }
}
```

## The mapper of a profile
`automapper.sh scaffold` writes `<Name>Mapper.cs` next to the profile, each map of AutoMapper translated: a `static partial class` (an instance class when a resolver of the profile takes services), one method per map, `To<Destination>` (`<Source>To<Type>` for a conversion to `string`, `int`…), `ApplyTo` for a map onto an existing object, `ProjectTo<Destination>` for a projection, the code of BeforeMap, AfterMap and Condition in a method around the generated one. A map it does not translate whole is quoted above its method with a TODO line: translate it with the forms below, take the quote out, build: each error names a member to map or to ignore. A method with nothing to configure stays a bare partial declaration: members by name, case ignored, flattened (`CustomerName` ← `Customer.Name`, `CustomerAddressCity` ← `Customer.Address.City`), nested objects and lists through the other methods of the mapper. The mapper of `OrderProfile` as the skill writes it (scaffold writes the same maps, with fewer comments: BeforeMap, AfterMap, Condition, NullSubstitute, MapFrom, Ignore, ReverseMap, ProjectTo, a map onto an existing object):
```csharp
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using Riok.Mapperly.Abstractions;
using Shop.Domain;
using Shop.Dtos;

namespace Shop.Mapping;

// The maps of the orders, generated at build time (the rules of every mapper of the project: MapperDefaults.cs)
[Mapper]
public static partial class OrderMapper
{
    // Amount: an expression of the source, through its helper (a private method, named by Use only)
    [MapPropertyFromSource(nameof(OrderLineDto.Amount), Use = nameof(Amount))]
    public static partial OrderLineDto ToOrderLineDto(this OrderLine source);

    // BeforeMap, Condition and AfterMap: the code around the generated method. Default = true: this method, never the
    // generated one, wherever an Order becomes an OrderDto (in a list, in another map)
    [UserMapping(Default = true)]
    public static OrderDto ToOrderDto(this Order source)
    {
        var target = new OrderDto();
        target.Audit = "mappé"; // BeforeMap
        MapOrder(source, target);
        if (source.Status == OrderStatus.Paid) // Condition: the member left as it is otherwise
        {
            target.Discount = source.Discount;
        }

        target.Summary = $"{target.Number} : {target.LineCount} ligne(s)"; // AfterMap
        return target;
    }

    // MapFrom and NullSubstitute: a member each, through its helper; the members of the method above ignored here
    [MapProperty(nameof(Order.CreatedAt), nameof(OrderDto.Created), Use = nameof(IsoDate))]
    [MapPropertyFromSource(nameof(OrderDto.LineCount), Use = nameof(LineCount))]
    [MapPropertyFromSource(nameof(OrderDto.Total), Use = nameof(Total))]
    [MapProperty(nameof(Order.Comment), nameof(OrderDto.Comment), Use = nameof(OrNone))]
    [MapProperty(nameof(Order.Lines), nameof(OrderDto.Lines), Use = nameof(LinesOrEmpty))]
    [MapperIgnoreTarget(nameof(OrderDto.Audit))]
    [MapperIgnoreTarget(nameof(OrderDto.Discount))]
    [MapperIgnoreTarget(nameof(OrderDto.Summary))]
    private static partial void MapOrder(Order source, OrderDto target);

    private static decimal Amount(OrderLine source) => source.Quantity * source.UnitPrice;

    private static string IsoDate(DateTime value) => value.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    private static int LineCount(Order source) => source.Lines == null ? 0 : source.Lines.Count;

    private static decimal Total(Order source) =>
        (source.Lines == null ? 0m : source.Lines.Sum(l => l.Quantity * l.UnitPrice)) - source.Discount;

    // NullSubstitute("(aucun)"): the helper takes the nullable type, so that it receives the null
    private static string OrNone(string? value) => value ?? "(aucun)";

    // a null list gives an empty one, as AutoMapper did (AllowNullCollections, false by default)
    private static List<OrderLineDto> LinesOrEmpty(List<OrderLine>? lines) =>
        lines == null ? new List<OrderLineDto>() : lines.Select(l => l.ToOrderLineDto()).ToList();

    // ReverseMap: a method each way, the way back unflattened by hand
    public static partial CustomerDto ToCustomerDto(this Customer source);

    [MapProperty(nameof(CustomerDto.AddressStreet), "Address.Street")]
    [MapProperty(nameof(CustomerDto.AddressCity), "Address.City")]
    public static partial Customer ToCustomer(this CustomerDto source);

    // ProjectTo: a method on IQueryable, translated into the query (only the columns of the DTO are read); its
    // configuration on a private method; a helper of a query is a single expression (inlined, RMG068 otherwise)
    public static partial IQueryable<OrderListItemDto> ProjectToOrderListItemDto(this IQueryable<Order> source);

    [MapPropertyFromSource(nameof(OrderListItemDto.LineCount), Use = nameof(CountLines))]
    private static partial OrderListItemDto ToOrderListItemDto(Order source);

    private static int CountLines(Order source) => source.Lines!.Count;

    // Map(update, order), MemberList.Source: onto the existing order, every member of the update mapped (RMG020
    // otherwise), the other members of the order kept; the condition of Comment (a patch: a null comment keeps that of
    // the order) around the generated method, its source and target members left to it
    public static void ApplyTo(this OrderUpdate source, Order target)
    {
        MapOrderUpdate(source, target);
        if (source.Comment != null)
        {
            target.Comment = source.Comment;
        }
    }

    [MapperRequiredMapping(RequiredMappingStrategy.Source)]
    [MapperIgnoreSource(nameof(OrderUpdate.Comment))]
    [MapperIgnoreTarget(nameof(Order.Comment))]
    private static partial void MapOrderUpdate(OrderUpdate source, [MappingTarget] Order target);

    [MapperIgnoreTarget(nameof(OrderLine.Id))]
    private static partial OrderLine ToOrderLine(OrderLineUpdate source);
}
```
The adapter of the tests, in the same step (each line calls the generated method; nothing else of the tests changes):
```csharp
using System.Linq;
using Shop.Domain;
using Shop.Dtos;
using Shop.Mapping;

namespace Shop.Tests.Mapping;

// The maps under test, through the generated mapper (the only test file that changed with it)
internal static class Mapped
{
    public static OrderDto ToOrderDto(Order source) => source.ToOrderDto();

    public static CustomerDto ToCustomerDto(Customer source) => source.ToCustomerDto();

    public static Customer ToCustomer(CustomerDto source) => source.ToCustomer();

    public static void ApplyTo(OrderUpdate source, Order target) => source.ApplyTo(target);

    public static IQueryable<OrderListItemDto> ProjectToOrderListItemDto(IQueryable<Order> source) =>
        source.ProjectToOrderListItemDto();
}
```
A profile whose resolver, converter or action takes services (the CONVERTER lines « takes services »): an instance mapper, those services in its constructor, its code in its methods; registered in place of `AddAutoMapper` (`services.AddScoped<InvoiceMapper>()`: the lifetime of its shortest-lived service; a static mapper needs nothing), injected where `IMapper` was. The mapper of `InvoiceProfile` (ConvertUsing, Include, ForCtorParam, a resolver with a service, a member named in another case):
```csharp
using System;
using System.Globalization;
using Riok.Mapperly.Abstractions;

namespace Billing;

// The maps of the invoices: an instance mapper, a resolver of the profile took a service (TaxResolver, ITaxRates)
[Mapper]
public partial class InvoiceMapper(ITaxRates rates)
{
    // Customer: MapFrom(s => s), the whole invoice through the map below; Tax: MapFrom<TaxResolver>(); REFERENCE from
    // Reference: names compared without case, as AutoMapper (MapperDefaults.cs)
    [MapPropertyFromSource(nameof(InvoiceDto.Customer), Use = nameof(ToCustomerSummary))]
    [MapPropertyFromSource(nameof(InvoiceDto.Tax), Use = nameof(Tax))]
    public partial InvoiceDto ToInvoiceDto(Invoice source);

    // ConvertUsing of Money -> string: every Money of this mapper becomes a string through this method
    [UserMapping(Default = true)]
    private static string Format(Money money) =>
        money.Amount.ToString("0.00", CultureInfo.InvariantCulture) + " " + money.Currency;

    // Include<CardPayment, CardPaymentDto>() and the others: one MapDerivedType per pair, on the method of the base types
    [MapDerivedType<CardPayment, CardPaymentDto>]
    [MapDerivedType<TransferPayment, TransferPaymentDto>]
    private partial PaymentDto ToPaymentDto(Payment source);

    // ForCtorParam("Label", ...): a constructor parameter is mapped as a member, by its name
    [MapPropertyFromSource(nameof(CustomerSummary.Label), Use = nameof(Label))]
    private partial CustomerSummary ToCustomerSummary(Invoice source);

    private static string Label(Invoice source) => source.CustomerLastName.ToUpperInvariant() + ", " + source.CustomerFirstName;

    // the code of TaxResolver.Resolve, its service from the constructor
    private decimal Tax(Invoice source) => Math.Round(source.Price.Amount * rates.RateFor(source.Country), 2);
}
```

## Each form of AutoMapper and its Mapperly equivalent
`automapper.sh scaffold` writes each of these it can; a form with a TODO line is written by hand as here. Mapster: the same list in the skill mapster.
- `CreateMap<S, D>()`: `public static partial D ToD(this S source);`. `Map<List<D>>(items)`: `items.Select(x => x.ToD()).ToList()`, or `public static partial List<D> ToDs(this IEnumerable<S> source);`.
- `ForMember(d => d.X, o => o.MapFrom(s => s.Y))`: `[MapProperty(nameof(S.Y), nameof(D.X))]`; a path: `[MapProperty("Customer.Name", nameof(D.X))]`; code on one member: `[MapProperty(nameof(S.Y), nameof(D.X), Use = nameof(Helper))]`; an expression of the source: `[MapPropertyFromSource(nameof(D.X), Use = nameof(Helper))]`. The helper: `private static`, its parameter of the exact source type (`string?` to receive a null), no attribute. A method `GetX()` that AutoMapper flattened into `X`: `[MapPropertyFromSource(nameof(D.X), Use = nameof(X))]`, `private static T X(S s) => s.GetX();`.
- `Ignore()`: `[MapperIgnoreTarget(nameof(D.X))]`; `ForSourceMember(s => s.Y, o => o.DoNotValidate())`: `[MapperIgnoreSource(nameof(S.Y))]`; `[Ignore]` on a member: `[MapperIgnore]`.
- `NullSubstitute(v)`: a helper `value ?? v` named by `Use`.
- `Condition(...)`, `PreCondition(...)`, `BeforeMap(...)`, `AfterMap(...)`, `AfterMap<TAction>()` (`IMappingAction`): the method around a `private static partial void` one (OrderMapper above): new target, the BeforeMap code, the generated method onto it, the conditions (`if (...) target.X = ...;`, the member ignored in the generated one), the AfterMap code, `[UserMapping(Default = true)]` on it. A BeforeMap that changes the source: before the call.
- `ReverseMap()`: a second method the other way, with its own attributes: its unflattening (`[MapProperty(nameof(D.CustomerName), "Customer.Name")]`) and its ignores. `ForPath(d => d.A.B, ...)`: `[MapProperty(source, "A.B")]`.
- `ConvertUsing(...)` or `ITypeConverter<S, D>` (a type into another, whole): a `[UserMapping(Default = true)]` method of the mapper. `ConvertUsing<IValueConverter>(s => s.Y)` (one member): `[MapProperty(nameof(S.Y), nameof(D.X), Use = nameof(Method))]`.
- `MapFrom<TResolver>()`, `IValueResolver`, `IMemberValueResolver`: the code of `Resolve` in a helper named by `Use`; its services: an instance mapper (InvoiceMapper above).
- `ConstructUsing(s => new D(...))`: `[ObjectFactory] private static D Create(S source) => new D(...);` (Mapperly maps the other members onto it; every D of the mapper is then built by it), or a `[UserMapping(Default = true)]` method that builds it all. `ForCtorParam("p", ...)`: `[MapProperty(source, "p")]` or `[MapPropertyFromSource("p", Use = ...)]` (a constructor parameter by name, case ignored).
- `Include<S1, D1>()`, `IncludeAllDerived()`: `[MapDerivedType<S1, D1>]` per pair on the method of the base types (an unknown derived type throws); `IncludeBase<B, BD>()` (a derived map takes the configuration of its base): `[IncludeMappingConfiguration(nameof(ToBaseDto))]`. `IncludeMembers(s => s.Inner)`: `[MapNestedProperties(nameof(S.Inner))]`.
- `CreateMap<S, D>(MemberList.Source)`, `ValidateMemberList(MemberList.Source)`: `[MapperRequiredMapping(RequiredMappingStrategy.Source)]` on the method.
- `Map(source, destination)`: `public static partial void ApplyTo(this S source, [MappingTarget] D target);` (OrderMapper). A list of the destination: AutoMapper cleared it and added into it, Mapperly assigns a new one (same content; an Entity Framework collection tracked: a wrapper that clears and adds). `UseDestinationValue()`: `[MapperIgnoreTarget]` on that method. A patch, `ForAllMembers(o => o.Condition((s, d, m) => m != null))`: a mapper class of its own, `[Mapper(AllowNullPropertyAssignment = false)]`.
- `ProjectTo<D>(configuration)`: `public static partial IQueryable<D> ProjectToD(this IQueryable<S> source);`, its attributes on a `private static partial D ToD(S source)` (OrderMapper); in a query: helpers of a single expression, no wrapper code (BeforeMap, AfterMap, Condition: in the query itself, or after it), no service, enums by value (a cast). Never `ToList()` then a map: it reads every column.
- `MaxDepth(n)`, `PreserveReferences()`: `[Mapper(UseReferenceHandling = true)]` (cycles; its reference handler is a run-time class: the PackageReference then without `ExcludeAssets="runtime"`).
- A runtime type, `Map(source, sourceType, destinationType)`: a typed call; otherwise `public static partial object Map(object source, Type targetType);` (Mapperly switches over the methods of the mapper). An open generic, `CreateMap(typeof(Page<>), typeof(PageDto<>))`: a generic method by hand, `public static PageDto<TDto> ToPageDto<T, TDto>(this Page<T> page, Func<T, TDto> map) => new(page.Items.Select(map).ToList(), page.Total);`.
- `opts.Items["key"]` (a value given at the call): an additional parameter of the method, matched by name to a target member (`public static partial D ToD(this S source, string culture);`; not passed to nested maps).
- The global settings (GLOBAL lines): `AllowNullCollections = true`: no `…OrEmpty` helper (Mapperly keeps a null); naming conventions (`LowerUnderscoreNamingConvention`), `RecognizePrefixes`, `ReplaceMemberName`: a `[MapProperty]` per member concerned; `AddGlobalIgnore("X")`, `ShouldMapProperty`: `[MapperIgnoreTarget]` per method, `[MapperIgnore]` on the member, or `IncludedMembers` of the mapper; `ValueTransformers`, `AddTransform<string>(s => s.Trim())`: no global equivalent, a helper per member concerned.
- Enums: AutoMapper parsed the name, case ignored, then fell back to the value; here by name, case ignored, and a source member missing on the target is a build error (RMG038): `[MapEnumValue(S.Old, D.Legacy)]` on a method of the enum pair (`private static partial D ToD(S source);`), or `[MapEnum(EnumMappingStrategy.ByName, FallbackValue = D.Unknown)]`.
- A date, a number into a string: AutoMapper and Mapperly call `ToString()` in the culture of the thread: the format and `CultureInfo.InvariantCulture` explicit, in a helper.
- A source member that may be null into a target member that may not (`string?` into `string`): AutoMapper wrote the null anyway, Mapperly leaves the member of the target as it is (its initializer); the « Nulls » snapshot shows it: a helper with the value AutoMapper gave. A null list: AutoMapper gave an empty one (`LinesOrEmpty`).
- A `MapFrom` whose expression meets a null on its way (`s => s.Customer.Name.ToUpper()`): AutoMapper caught it and gave the default value; Mapperly and Mapster throw `NullReferenceException`: the « Nulls » snapshot (`nulls: true`) shows it; the null check written in the expression (`s.Customer == null ? null : s.Customer.Name.ToUpper()`).

## The callers, the registration and the last step (Mapperly)
- `mapper.Map<OrderDto>(order)` → `order.ToOrderDto()`; `mapper.Map(update, order)` → `update.ApplyTo(order)`; `query.ProjectTo<OrderListItemDto>(mapper.ConfigurationProvider)` → `query.ProjectToOrderListItemDto()`. The `IMapper` of a constructor: removed (static mapper) or replaced by the instance mapper; `services.AddAutoMapper(...)` → `services.AddScoped<InvoiceMapper>()` for each instance mapper, nothing for a static one.
- A test that mocks `IMapper` (`Mock<IMapper>`, `Substitute.For<IMapper>()`): the test-guardian rewrites it in the step of its class (mission « filet »), with the real mapper: no setup of a map, the expected values from it.
- The last step: the profiles, resolvers, converters, actions and `AddAutoMapper` removed, the test of `AssertConfigurationIsValid` too (the build does it now), the AutoMapper packages out of the projects and of `Directory.Packages.props`; a library that had `Microsoft.Extensions.DependencyInjection.Abstractions` or `Microsoft.Extensions.Options` only through AutoMapper: its own PackageReference (the build says CS0246). Done when `automapper.sh check` says « AUTOMAPPER: GONE » and the build and every test pass; `Mapped.cs` stays, on the mapper.
