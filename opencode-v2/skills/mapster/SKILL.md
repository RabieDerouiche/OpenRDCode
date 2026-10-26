---
name: mapster
description: AutoMapper replaced by Mapster (« Cible : Mapster », the closest to AutoMapper - the same model at run time, IMapper and its calls kept) - MapsterSetup.cs and the rules of AutoMapper, the Register of each profile written by automapper.sh scaffold --mapster (ForMember, MapFrom, Ignore, Condition into IgnoreIf, NullSubstitute, BeforeMap, AfterMap, ReverseMap, ConvertUsing, Include, ForCtorParam, a resolver with a service, Items), the adapter of the snapshot tests, the test that replaces AssertConfigurationIsValid, automapper.sh switch and the last step. Load with the skill automapper when the target is Mapster, before writing, fixing, reviewing or testing code that uses Mapster.
compatibility: opencode
---
# AutoMapper → Mapster

The skill `automapper` holds what both targets share: why AutoMapper leaves, the choice of the target, the flow of /go, the snapshot tests recorded on AutoMapper (their helpers, `record`, the seal). This one is the target « Cible : Mapster »: Mapster (MIT, `Mapster` and `Mapster.DependencyInjection`), the closest to AutoMapper. Its configuration is code run once at start-up, each map compiled into a delegate on its first use (fast: no reflection per call), `IMapper` with the same methods as that of AutoMapper (`Map<D>(source)`, `Map(source, destination)`, `Map(source, sourceType, destinationType)`): the calls, the constructors that take `IMapper` and the tests that mock it do not change, only their `using`. What it does not do that Mapperly does: a member forgotten is found by a test (below), not by the build; the package runs with the application; no Native AOT.

## How the pack runs it
- the pilot, when /go starts (« Cible : Mapster »): `sh ~/.config/opencode/scripts/automapper.sh setup --mapster <each project of the PROJECTS line>` and its commit: `Mapster` and `Mapster.DependencyInjection` (their version in `Directory.Packages.props` when versions are central), and `MapsterSetup.cs` once, in the first of these projects (the application owns it). A STOP on `Microsoft.Extensions.DependencyInjection.Abstractions` older than 9.0.0 (`Mapster.DependencyInjection` needs it, on net8.0 too: the restore would fail, NU1605): the developer raises it, then setup again.
- the test-guardian, before the first profile (mission « filet »), with the snapshot tests of the skill `automapper`: the test that replaces `AssertConfigurationIsValid` (below), sealed with them (green before the first Register: there is nothing to check yet). The adapter of the tests (`Mapped.cs`) on AutoMapper, as in the skill `automapper`.
- the coder, each profile: `sh ~/.config/opencode/scripts/automapper.sh scaffold --mapster <the profile file>` writes `<Name>Register.cs` next to it, each map translated; a map it does not translate whole is quoted above its code with a TODO line: finish it (the forms below), take the quote out. Then `Mapped.cs` on Mapster. The step is done when the build, the test of the Registers and the sealed tests pass as they are, twice. The callers stay on `IMapper` and the profile stays: AutoMapper still maps the application until the last step.
- the last step: `sh ~/.config/opencode/scripts/automapper.sh switch` (below), then the profiles, resolvers, converters and AutoMapper packages removed until `automapper.sh check` says « AUTOMAPPER: GONE », the build and every test green.
- the checker: a TODO line left in a Register, a Register changed to make a sealed test pass by a means other than the mapping (a `MapWith` that returns a fixed value…), `MapsterSetup.cs` changed: « bloquant ».

## MapsterSetup.cs: the rules of AutoMapper
Written by `automapper.sh setup --mapster`: `Configure(config, strict, assemblies)` gives a configuration the rules of every map as AutoMapper mapped (member names compared without case, `CustomerName` ← `Customer.Name` flattened, enums by name, a null list mapped to an empty one: `DestinationTransform.EmptyCollectionIfNull`; kept null when the code sets `AllowNullCollections = true`), then the `IRegister` classes of the assemblies, each assembly once. `AddMapsterMaps(this IServiceCollection, params Type[] markers)` replaces `AddAutoMapper`: the Registers of the assemblies of these types into `TypeAdapterConfig.GlobalSettings` (also what `Adapt()` and `ProjectToType()` without configuration use), and `IMapper` as a `ServiceMapper` of the scope: `MapContext.Current.GetService<T>()` in a map gives the services of the scope that maps. Never changed to make a test pass.

## The Register of a profile
What `automapper.sh scaffold --mapster src/Shop/Mapping/OrderProfile.cs` writes (nothing to finish: every form of this profile is translated):
```csharp
using System.Globalization;
using Mapster;
using Shop.Domain;
using Shop.Dtos;

namespace Shop.Mapping;

// The maps of OrderProfile for Mapster (written by automapper.sh scaffold --mapster; the application
// owns it): each map of AutoMapper translated; a map quoted above its code has TODO lines to finish
// (the skill mapster). The rules of every map, as AutoMapper mapped: MapsterSetup.cs.
public class OrderRegister : IRegister
{
    public void Register(TypeAdapterConfig config)
    {
        config.NewConfig<OrderLine, OrderLineDto>()
            .Map(d => d.Amount, s => s.Quantity * s.UnitPrice)
            ;

        config.NewConfig<Order, OrderDto>()
            .Map(d => d.Created, s => s.CreatedAt.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture))
            .Map(d => d.LineCount, s => s.Lines == null ? 0 : s.Lines.Count)
            .Map(d => d.Total, s => (s.Lines == null ? 0m : s.Lines.Sum(l => l.Quantity * l.UnitPrice)) - s.Discount)
            .IgnoreIf((s, _) => !(s.Status == OrderStatus.Paid), d => d.Discount)
            .Map(d => d.Comment, s => s.Comment ?? "(aucun)")
            .Ignore(d => d.Audit)
            .Ignore(d => d.Summary)
            .BeforeMapping((s, d) => d.Audit = "mappé")
            .AfterMapping((s, d) => d.Summary = $"{d.Number} : {d.LineCount} ligne(s)")
            ;

        config.NewConfig<Customer, CustomerDto>()
            ;

        config.NewConfig<CustomerDto, Customer>()
            .Unflattening(true)
            .RequireDestinationMemberSource(false)
            ;

        config.NewConfig<Order, OrderListItemDto>()
            .Map(d => d.LineCount, s => s.Lines!.Count)
            ;

        config.NewConfig<OrderLineUpdate, OrderLine>()
            .Ignore(d => d.Id)
            ;

        config.NewConfig<OrderUpdate, Order>()
            .RequireDestinationMemberSource(false)
            .IgnoreIf((s, _) => !(s.Comment != null), d => d.Comment)
            ;
    }
}
```
The Register of `InvoiceProfile`, its TODO line finished (`MapFrom<TaxResolver>()`: the code of `Resolve`, its service from the scope that maps):
```csharp
using System;
using System.Globalization;
using Mapster;

namespace Billing;

// The maps of InvoiceProfile for Mapster (written by automapper.sh scaffold --mapster; the application
// owns it): each map of AutoMapper translated; a map quoted above its code has TODO lines to finish
// (the skill mapster). The rules of every map, as AutoMapper mapped: MapsterSetup.cs.
public class InvoiceRegister : IRegister
{
    public void Register(TypeAdapterConfig config)
    {
        config.NewConfig<Money, string>()
            .MapWith(m => m.Amount.ToString("0.00", CultureInfo.InvariantCulture) + " " + m.Currency)
            ;

        config.NewConfig<Payment, PaymentDto>()
            .Include<CardPayment, CardPaymentDto>()
            .Include<TransferPayment, TransferPaymentDto>()
            ;

        config.NewConfig<CardPayment, CardPaymentDto>()
            ;

        config.NewConfig<TransferPayment, TransferPaymentDto>()
            ;

        config.NewConfig<Invoice, CustomerSummary>()
            .Map(nameof(CustomerSummary.Label), s => s.CustomerLastName.ToUpperInvariant() + ", " + s.CustomerFirstName)
            ;

        // MapFrom<TaxResolver>(): the code of TaxResolver.Resolve; ITaxRates from the scope of the IMapper that maps
        // (AddMapsterMaps: a ServiceMapper; Adapt() has no services: it throws there)
        config.NewConfig<Invoice, InvoiceDto>()
            .Map(d => d.Customer, s => s)
            .Map(d => d.Tax, s =>
                Math.Round(s.Price.Amount * MapContext.Current.GetService<ITaxRates>().RateFor(s.Country), 2))
            ;
    }
}
```

## The tests
The adapter of the snapshot tests, in the step of the profile (each line through Mapster, configured by `MapsterSetup` as the application will be; nothing else of the tests changes). A Register whose maps take services: through the container, `new ServiceCollection().AddSingleton<ITaxRates, FixedTaxRates>().AddMapsterMaps(typeof(InvoiceRegister)).BuildServiceProvider().GetRequiredService<IMapper>()`, the services given test values.
```csharp
using System.Linq;
using Mapster;
using MapsterMapper;
using Shop.Domain;
using Shop.Dtos;
using Shop.Mapping;

namespace Shop.Tests.Mapping;

// The maps under test, through Mapster configured as the application is (MapsterSetup: the rules of AutoMapper, the
// Registers of the assembly). The only test file that changed with the mapping
internal static class Mapped
{
    private static readonly TypeAdapterConfig Config =
        MapsterSetup.Configure(new TypeAdapterConfig(), false, typeof(OrderRegister).Assembly);
    private static readonly IMapper Mapper = new Mapper(Config);

    public static OrderDto ToOrderDto(Order source) => Mapper.Map<OrderDto>(source);

    public static CustomerDto ToCustomerDto(Customer source) => Mapper.Map<CustomerDto>(source);

    public static Customer ToCustomer(CustomerDto source) => Mapper.Map<Customer>(source);

    public static void ApplyTo(OrderUpdate source, Order target) => Mapper.Map(source, target);

    public static IQueryable<OrderListItemDto> ProjectToOrderListItemDto(IQueryable<Order> source) =>
        source.ProjectToType<OrderListItemDto>(Config);
}
```
The test that replaces `AssertConfigurationIsValid`, written by the test-guardian with the first profile (xUnit; MSTest: `[TestMethod]`; NUnit: `[Test]`); one marker type per project of the PROJECTS line:
```csharp
using Mapster;
using Xunit;

namespace Shop.Tests.Mapping;

// Every map of the Registers complete, as the validation of the configuration of AutoMapper checked it: a target
// member without source nor Ignore fails here, with its map and its member (at run time Mapster leaves it as it is,
// as AutoMapper did)
public class MapsterConfigurationTests
{
    [Fact]
    public void EveryMap_HasASourceForEachMember() =>
        MapsterSetup.Configure(new TypeAdapterConfig(), true, typeof(MapsterSetup).Assembly).Compile(failFast: false);
}
```

## Each form of AutoMapper and its Mapster equivalent
`automapper.sh scaffold --mapster` writes each of these; a form with a TODO line is written by hand as here.
- `CreateMap<S, D>()`: `config.NewConfig<S, D>()` (a map with nothing to configure may go: Mapster maps any pair by name, but `NewConfig` puts it under the test of the Registers). `CreateMap(typeof(Page<>), typeof(PageDto<>))`: `config.NewConfig(typeof(Page<>), typeof(PageDto<>))`.
- `ForMember(d => d.X, o => o.MapFrom(s => s.Y))`: `.Map(d => d.X, s => s.Y)`; `MapFrom("Y")`: `.Map(d => d.X, s => s.Y)`; `Ignore()`: `.Ignore(d => d.X)`; `ForPath(d => d.A.B, ...)`: `.Map(d => d.A.B, ...)`; `[Ignore]` on a member: `[AdaptIgnore]`, or `.Ignore` in its map.
- `NullSubstitute(v)`: `.Map(d => d.X, s => s.X ?? v)`.
- `Condition(s => c)`, `PreCondition(s => c)`, `Condition((s, d) => c)`: `.IgnoreIf((s, d) => !(c), d => d.X)`: the member left as it is when the condition is false, as AutoMapper did; never the third argument of `Map(d => d.X, s => s.Y, s => c)`, which sets the member to its default value when false (a « Order.Updated » or « OrderDto.Draft » snapshot shows the difference). A condition on the member value (`(s, d, m) => m != null`): `IgnoreIf((s, d) => s.Y == null, d => d.X)`; on every member, `ForAllMembers(o => o.Condition((s, d, m) => m != null))`: `.IgnoreNullValues(true)`.
- `BeforeMap((s, d) => ...)`, `AfterMap((s, d) => ...)`: `.BeforeMapping((s, d) => ...)`, `.AfterMapping((s, d) => ...)`, same order, same moment (the target created, before or after its members). `AfterMap<TAction>()` (`IMappingAction`): its code in the lambda, its services by `MapContext.Current.GetService<T>()`. The `ResolutionContext` of the lambda: `MapContext.Current` (`Parameters`, `GetService<T>()`).
- `ReverseMap()`: a second `NewConfig<D, S>()` with `.Unflattening(true)` (`CustomerName` → `Customer.Name`, as AutoMapper) and `.RequireDestinationMemberSource(false)` (AutoMapper never checked the way back), and the simple `MapFrom` of the way there reversed (`.Map(s => s.Y, d => d.X)`).
- `ConvertUsing(s => ...)`, `ITypeConverter<S, D>`: `.MapWith(s => ...)` (the whole type; a converter with services: `MapContext.Current.GetService<T>()` in it). `ConvertUsing<IValueConverter>(s => s.Y)` (one member): `.Map(d => d.X, s => Convert(s.Y))`.
- `MapFrom<TResolver>()`, `IValueResolver`, `IMemberValueResolver`: `.Map(d => d.X, s => <the code of Resolve>)`, its services by `MapContext.Current.GetService<T>()` (InvoiceRegister above): the map then runs through the `IMapper` of the container (`AddMapsterMaps`), never `Adapt()`.
- `ConstructUsing(s => new D(...))`: `.ConstructUsing(s => new D(...))`. `ForCtorParam("p", o => o.MapFrom(s => ...))`: `.Map("p", s => ...)` (a constructor parameter is mapped by its name, case ignored).
- `Include<S1, D1>()`: `.Include<S1, D1>()` on the map of the base types; `IncludeBase<B, BD>()`: `.Inherits<B, BD>()`; `IncludeAllDerived()`: an `.Include` per derived pair; `IncludeMembers(s => s.Inner)`: a `.Map(d => d.X, s => s.Inner.X)` per member that comes from `Inner`.
- `CreateMap<S, D>(MemberList.Source)`, `ValidateMemberList(MemberList.None)`: `.RequireDestinationMemberSource(false)` (Mapster checks the target members only; a source member left out is not reported: a snapshot of a source with every member set shows it).
- `MaxDepth(n)`: `.MaxDepth(n)`; `PreserveReferences()`: `.PreserveReference(true)`; `UseDestinationValue()`: `.UseDestinationValue(m => m.Name == nameof(D.X))`.
- `Map(source, destination)`: the same call (`IMapper.Map(source, destination)`, `source.Adapt(destination)`); a list of the target: AutoMapper cleared it and added into it, Mapster assigns a new one with the same content (an Entity Framework collection tracked: `.UseDestinationValue` and a `MapToTargetWith`).
- `ProjectTo<D>(mapper.ConfigurationProvider)`: `ProjectToType<D>(mapper.Config)` (`automapper.sh switch`); in a query: an expression the database can run (no `BeforeMapping`, `AfterMapping`, service or `MapWith` of code), as AutoMapper.
- `opts.Items["key"] = v` at the call, `context.Items["key"]` in the map: `mapper.From(source).AddParameters("key", v).AdaptToType<D>()` at the call, `MapContext.Current!.Parameters["key"]` in the map.
- The global settings (GLOBAL lines): `AllowNullCollections = true`: no `EmptyCollectionIfNull` (setup leaves it out when it finds it); `SourceMemberNamingConvention`/`DestinationMemberNamingConvention`: `config.Default.NameMatchingStrategy(NameMatchingStrategy.ConvertSourceMemberName(...))`; `RecognizePrefixes("Get")`, `ReplaceMemberName`: `.Map` per member concerned, or `GetMemberName`; `AddGlobalIgnore("X")`, `ShouldMapProperty`: `config.Default.IgnoreMember((m, side) => ...)`; `ValueTransformers`, `AddTransform<string>(s => s.Trim())`: `.AddDestinationTransform((string s) => s.Trim())` on the map or on `config.Default`.
- Enums: by name, case ignored (MapsterSetup), as AutoMapper; a source member without a target member of its name: AutoMapper gave the value, Mapster throws a `FormatException` when it maps it, and the test of the Registers does not see it: `config.NewConfig<S, D>().MapWith(s => <a switch>)` for that pair of enums, or the member added to the target.
- A date, a number into a string: AutoMapper and Mapster call `ToString()` in the culture of the thread: the format and `CultureInfo.InvariantCulture` explicit.

## The last step: `automapper.sh switch`
Once every profile has its Register and its tests green: `sh ~/.config/opencode/scripts/automapper.sh switch` rewrites the code that used AutoMapper (the profiles and resolvers left out, they leave with it): `using AutoMapper;` → `using MapsterMapper;`, `using AutoMapper.QueryableExtensions;` → `using Mapster;`; `ProjectTo<D>(mapper.ConfigurationProvider)` → `ProjectToType<D>(mapper.Config)`, `mapper.ProjectTo<D>(query)` → `query.ProjectToType<D>(mapper.Config)`; `services.AddAutoMapper(typeof(OrderProfile))` → `services.AddMapsterMaps(typeof(OrderRegister))` (a lambda that only adds profiles or sets the license key too); in the tests, `new MapperConfiguration(cfg => cfg.AddProfile<OrderProfile>())` → `MapsterSetup.Configure(new TypeAdapterConfig(), ..., typeof(OrderRegister).Assembly)`, `CreateMapper()` → `new Mapper(config)`, `AssertConfigurationIsValid()` → `Compile(failFast: false)` on a strict configuration; `IConfigurationProvider`, `MapperConfiguration` → `TypeAdapterConfig`. A SWITCHED line per file; a LEFT line for what it does not rewrite (a configuration of AutoMapper beyond profiles, `opts.Items`, a `ProjectTo` with more arguments): by hand, with the forms above. The calls of `IMapper` and the tests that mock it do not change. Then: the build; the profiles, resolvers, converters and actions removed; the AutoMapper packages out of the projects and of `Directory.Packages.props` (and its license key out of the configuration); until `automapper.sh check` says « AUTOMAPPER: GONE », the build and every test green, the test of the Registers too.
