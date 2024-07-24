defmodule ExNominatim.Validations do
  alias ExNominatim.Client.{SearchParams, ReverseParams, StatusParams}

  # Source: https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2#Officially_assigned_code_elements
  @iso_3166_1_alpha2 String.split(
                       "ad,ae,af,ag,ai,al,am,ao,aq,ar,as,at,au,aw,ax,az,ba,bb,bd,be,bf,bg,bh,bi,bj,bl,bm,bn,bo,bq,br,bs,bt,bv,bw,by,bz,ca,cc,cd,cf,cg,ch,ci,ck,cl,cm,cn,co,cr,cu,cv,cw,cx,cy,cz,de,dj,dk,dm,do,dz,ec,ee,eg,eh,er,es,et,fi,fj,fk,fm,fo,fr,ga,gb,gd,ge,gf,gg,gh,gi,gl,gm,gn,gp,gq,gr,gs,gt,gu,gw,gy,hk,hm,hn,hr,ht,hu,id,ie,il,im,in,io,iq,ir,is,it,je,jm,jo,jp,ke,kg,kh,ki,km,kn,kp,kr,kw,ky,kz,la,lb,lc,li,lk,lr,ls,lt,lu,lv,ly,ma,mc,md,me,mf,mg,mh,mk,ml,mm,mn,mo,mp,mq,mr,ms,mt,mu,mv,mw,mx,my,mz,na,nc,ne,nf,ng,ni,nl,no,np,nr,nu,nz,om,pa,pe,pf,pg,ph,pk,pl,pm,pn,pr,ps,pt,pw,py,qa,re,ro,rs,ru,rw,sa,sb,sc,sd,se,sg,sh,si,sj,sk,sl,sm,sn,so,sr,ss,st,sv,sx,sy,sz,tc,td,tf,tg,th,tj,tk,tl,tm,tn,to,tr,tt,tv,tw,tz,ua,ug,um,us,uy,uz,va,vc,ve,vg,vi,vn,vu,wf,ws,ye,yt,za,zm,zw",
                       ","
                     )

  # Source: https://en.wikipedia.org/wiki/List_of_ISO_639_language_codes#Table
  @iso_639_1_set1 String.split(
                    "ab,aa,af,ak,sq,am,ar,an,hy,as,av,ae,ay,az,bm,ba,eu,be,bn,bi,bs,br,bg,my,ca,ch,ce,ny,zh,cu,cv,kw,co,cr,hr,cs,da,dv,nl,dz,en,eo,et,ee,fo,fj,fi,fr,fy,ff,gd,gl,lg,ka,de,el,kl,gn,gu,ht,ha,he,hz,hi,ho,hu,is,io,ig,id,ia,ie,iu,ik,ga,it,ja,jv,kn,kr,ks,kk,km,ki,rw,ky,kv,kg,ko,kj,ku,lo,la,lv,li,ln,lt,lu,lb,mk,mg,ms,ml,mt,gv,mi,mr,mh,mn,na,nv,nd,nr,ng,ne,no,nb,nn,oc,oj,or,om,os,pi,ps,fa,pl,pt,pa,qu,ro,rm,rn,ru,se,sm,sg,sa,sc,sr,sn,sd,si,sk,sl,so,st,es,su,sw,ss,sv,tl,ty,tg,ta,tt,te,th,bo,ti,to,ts,tn,tr,tk,tw,ug,uk,ur,uz,ve,vi,vo,wa,cy,wo,xh,yi,yo,za,zu",
                    ","
                  )

  @structured_query_fields [:amenity, :street, :city, :county, :state, :country, :postalcode]

  def validate(m) when is_struct(m) do
    with %{valid?: true} = validated <- validate_all_fields(m),
         %{valid?: true} = verified <- verify_intent(validated) do
      {:ok, sanitize_comma_separated_strings(verified)}
    else
      %{valid?: false} = mi -> {:error, mi}
    end
  end

  def verify_intent(%StatusParams{} = m), do: m

  def verify_intent(%SearchParams{} = m) do
    is_freeform = not is_nil(m.q)

    is_structured =
      extract_structured_field_values(m)
      |> Enum.filter(&(!is_nil(&1)))
      |> List.to_string()
      |> Kernel.!=("")

    message = "Must set either freeform or structured query parameters (and not both)"

    case {is_freeform, is_structured} do
      {true, false} -> m
      {false, true} -> m
      {false, false} -> invalidate(m, :missing_query_params, message)
      {true, true} -> invalidate(m, :confusing_intent, message)
    end
  end

  def verify_intent(%ReverseParams{} = m) do
    %{lat: lat, lon: lon} = Map.take(m, [:lat, :lon])

    coords_ok? =
      [lat, lon]
      |> Enum.map(fn x ->
        cond do
          is_nil(x) -> false
          is_float(x) -> true
          nonempty_string?(x) -> true
          true -> false
        end
      end)
      |> cumulative_and()

    case coords_ok? do
      [true, true] ->
        m

      [false, true] ->
        invalidate(m, :missing_query_params, explain(:lat))

      [true, false] ->
        invalidate(m, :missing_query_params, explain(:lon))

      [false, false] ->
        invalidate(m, :missing_query_params, "Both latitude and longitude are required")
    end
  end

  def invalidate(m, err_key, err_msg)
      when is_struct(m) and is_atom(err_key) and is_bitstring(err_msg) do
    %{m | valid?: false, errors: [{err_key, err_msg} | m.errors]}
  end

  def extract_structured_field_values(p) when is_map(p) do
    Map.take(p, @structured_query_fields) |> Map.values()
  end

  def validate_all_fields(m) when is_struct(m) do
    permitted_keys(m)
    |> Enum.reduce(
      %{m | valid?: true, errors: []},
      fn k, acc ->
        case validate_field(k, acc) do
          {:ok, _} -> %{acc | valid?: acc.valid? and true}
          {:error, {err_key, err_msg}} -> invalidate(acc, err_key, err_msg)
        end
      end
    )
  end

  def validate_field(k, m) when is_atom(k) and is_map(m) do
    with {:permitted?, true} <- {:permitted?, k in permitted_keys(m)},
         {:valid?, {true, _}} <- {:valid?, valid?(Map.get(m, k), k)} do
      {:ok, m}
    else
      {:permitted?, false} -> {:error, {k, :invalid_key}}
      {:valid?, {false, message}} -> {:error, {k, message}}
    end
  end

  def valid?(v, _) when is_nil(v), do: {true, nil}

  def valid?(v, coord) when coord in [:lat, :lon] do
    message = explain(coord)

    lim = limits(coord)

    cond do
      is_float(v) and valid_number_value_ranged?(v, lim[:crit], limits(coord)) ->
        {true, message}

      nonempty_string?(v) ->
        case Float.parse(v) do
          :error -> {false, message}
          {vf, _} -> valid?(vf, coord)
        end

      true ->
        {false, message}
    end
  end

  def valid?(v, :polygon_threshold = k) do
    message = explain(k)

    cond do
      is_float(v) ->
        {true, message}

      nonempty_string?(v) ->
        case Float.parse(v) do
          :error -> {false, message}
          {vf, _} -> valid?(vf, k)
        end

      true ->
        {false, message}
    end
  end

  def valid?(v, bitstring_field)
      when bitstring_field in [
             :q,
             :amenity,
             :street,
             :city,
             :county,
             :state,
             :country,
             :postalcode
           ] do
    message = explain(bitstring_field)

    cond do
      nonempty_string?(v) -> {true, message}
      is_nil(v) -> {true, message}
      true -> {false, message}
    end
  end

  def valid?(v, zero_one_field)
      when zero_one_field in [
             :addressdetails,
             :extratags,
             :namedetails,
             :bounded,
             :polygon_geojson,
             :polygon_kml,
             :polygon_svg,
             :polygon_text,
             :dedupe,
             :debug
           ] do
    message = explain(zero_one_field)
    {valid_integer_value_discrete?(v), message}
  end

  def valid?(v, :format = k) do
    {
      v in ~w|xml json jsonv2 geojson geocodejson|,
      explain(k)
    }
  end

  def valid?(v, :featureType = k) do
    {
      v in ~w|country state city settlement|,
      explain(k)
    }
  end

  def valid?(v, :layer = k) do
    layers = ~w|address poi railway natural manmade|

    {
      comma_separated_strings_to_list(v)
      |> Enum.map(fn x -> x in layers end)
      |> cumulative_and(),
      explain(k)
    }
  end

  def valid?(v, :countrycodes = k) do
    message = explain(k)

    if is_bitstring(v) do
      {
        comma_separated_strings_to_list(v)
        |> Enum.map(&Kernel.in(&1, @iso_3166_1_alpha2))
        |> cumulative_and(),
        message
      }
    else
      {false, message}
    end
  end

  def valid?(v, :limit = k) do
    {
      is_integer(v) and valid_number_value_ranged?(v, :gtelte, mn: 1, mx: 40),
      explain(k)
    }
  end

  def valid?(v, :zoom = k) do
    {
      is_integer(v) and
        valid_integer_value_discrete?(v, List.flatten([3, 5, 8, 10] ++ Enum.uniq(12..18))),
      explain(k)
    }
  end

  def valid?(v, :email = k) do
    message = explain(k)

    if is_bitstring(v) do
      {
        Regex.match?(~r/^[A-Za-z0-9._%+\-+']+@[A-Za-z0-9.-]+\.[A-Za-z]+$/, v),
        message
      }
    else
      {false, message}
    end
  end

  def valid?(v, :accept_language = k) do
    message = explain(k)

    if is_bitstring(v) do
      {
        comma_separated_strings_to_list(v)
        |> Enum.map(&Kernel.in(&1, @iso_639_1_set1))
        |> cumulative_and(),
        message
      }
    else
      {false, message}
    end
  end

  def valid?(_, _), do: {true, nil}

  def valid_integer_value_discrete?(v, valid_values \\ [0, 1])

  def valid_integer_value_discrete?(v, valid_values)
      when is_integer(v) and is_list(valid_values) do
    v in valid_values
  end

  def valid_integer_value_discrete?(v, valid_values) when is_bitstring(v) do
    {vi, _} = Integer.parse(v)
    valid_integer_value_discrete?(vi, valid_values)
  end

  def valid_number_value_ranged?(v, crit, opts \\ [mn: 0, mx: 40])

  def valid_number_value_ranged?(v, crit, opts)
      when is_number(v) and is_list(opts) and
             crit in [:gt, :gte, :gtelt, :gtelte] do
    mn = Keyword.get(opts, :mn)
    mx = Keyword.get(opts, :mx)

    case crit do
      :gte -> v >= mn
      :gt -> v > mn
      :gtelt -> v >= mn and v < mx
      :gtelte -> v >= mn and v <= mx
    end
  end

  def valid_number_value_ranged?(v, crit, opts)
      when is_number(v) and is_list(opts) and
             crit in [:gtlte, :gtlt, :lt, :lte] do
    mn = Keyword.get(opts, :mn)
    mx = Keyword.get(opts, :mx)

    case crit do
      :gtlte -> v > mn and v <= mx
      :gtlt -> v > mn and v < mx
      :lt -> v < mx
      :lte -> v <= mx
    end
  end

  def valid_number_value_ranged?(v, crit, opts) when is_bitstring(v) do
    vt =
      case Keyword.get(opts, :type) do
        :integer -> Integer.parse(v)
        :float -> Float.parse(v)
        _ -> :error
      end

    case vt do
      :error -> false
      {vt_ok, _} -> valid_number_value_ranged?(vt_ok, crit, opts)
    end
  end

  def permitted_keys(m) when is_struct(m) do
    m |> Map.from_struct() |> Map.keys() |> Kernel.--([:valid?, :errors])
  end

  def comma_separated_strings_to_list(v) when is_bitstring(v) do
    v
    |> String.downcase()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end

  def cumulative_and(list) when is_list(list) do
    Enum.reduce(list, true, fn x, acc -> x and acc end)
  end

  def sanitize_comma_separated_strings(query) when is_struct(query) do
    [:layer, :countrycodes, :exclude_place_ids, :viewbox]
    |> Enum.reduce(
      query,
      fn k, acc ->
        v = Map.get(acc, k)

        if is_bitstring(v) do
          Map.put(
            acc,
            k,
            v
            |> collapse_spaces()
            |> String.trim(",")
          )
        else
          acc
        end
      end
    )
  end

  def nonempty_string?(s) do
    is_bitstring(s) and s != ""
  end

  def collapse_spaces(s) when is_bitstring(s) do
    s
    |> String.split(" ")
    |> Enum.reject(&(&1 == ""))
    |> List.to_string()
  end

  def limits(:lat), do: [mn: -90.0, mx: 90.0, crit: :gtelte]
  def limits(:lon), do: [mn: -180.0, mx: 180.0, crit: :gtelt]

  def explain(k) when is_atom(k) do
    zero_or_one = ", 0 or 1"

    opt_sq = " (optional for structured query)"

    %{
      q: "Free-form query string to search for (mutually exclusive with structured query fields)",
      amenity: "Name and/or type of POI" <> opt_sq,
      street: "Housenumber and streetname" <> opt_sq,
      city: "City" <> opt_sq,
      county: "County" <> opt_sq,
      state: "State" <> opt_sq,
      country: "Country" <> opt_sq,
      postalcode: "Postal code" <> opt_sq,
      limit: "Limit the maximum number of returned results. Integer, 1 to 40" <> default(10),
      addressdetails:
        "Include a breakdown of the address into elements" <> zero_or_one <> default(0),
      extratags:
        "Include any additional information in the result that is available in the database" <>
          zero_or_one <> default(0),
      namedetails: "Include a full list of names for the result" <> zero_or_one <> default(0),
      accept_language:
        "Browser language string consisting of ISO 639-1 Set 1 codes" <>
          default("content of Accept-Language HTTP header"),
      countrycodes: "Comma-separated list of ISO 3166-1 alpha-2 country codes" <> default(),
      layer:
        "Comma-separated list of: address, poi, railway, natural, manmade" <>
          default() <> " (no restriction)",
      featureType: "One of: country, state, city, settlement" <> default(),
      exclude_place_ids: "Comma-separated list of place_id items to skip" <> default(),
      viewbox:
        "Boost parameter which focuses the search on the given area. <x1>,<y1>,<x2>,<y2> where x is longitude and y is latitude" <>
          default(),
      bounded: "Exclude any results outside the viewbox" <> zero_or_one <> default(0),
      polygon_geojson: polygon_output_message("GeoJSON"),
      polygon_kml: polygon_output_message("KML"),
      polygon_svg: polygon_output_message("SVG"),
      polygon_text: polygon_output_message("text"),
      polygon_threshold:
        "Tolerance in degrees with which the simplified geometry may differ from the original geometry, floating-point number" <>
          default(0.0),
      email: "Valid email address (if making a large number of requests)" <> default(),
      dedupe: "Toggle the deduplication mechanism" <> zero_or_one <> default(1),
      debug: "Output assorted developer debug information in HTML" <> zero_or_one <> default(0),
      lat: "Floating-point number in range [-90, 90] (or its string representation)",
      lon: "Floating-point number in range [-180, 180) (or its string representation)",
      zoom: "Level of detail required for the address [3, 5, 8, 10, 12..18]" <> default(18),
      format:
        "One of: xml, json, jsonv2, geojson, geocodejson (Default: jsonv2 for /search, xml for /reverse)"
    }
    |> Map.get(k)
  end

  def polygon_output_message(format) when is_bitstring(format) do
    "Polygon output in " <> format <> ", 0 or 1" <> default(0)
  end

  def default(v) when is_bitstring(v) do
    " (Default: " <> v <> ")"
  end

  def default(v) when is_number(v), do: default(to_string(v))

  def default, do: default("unset")
end
