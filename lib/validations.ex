# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Validations do
  alias ExNominatim.Client.{
    SearchParams,
    ReverseParams,
    StatusParams,
    DetailsParams,
    LookupParams
  }

  @moduledoc """
  Functions used for the automatic validation of the keys of a request parameters struct according to the target endpoint, their values according to the API endpoint's specification, and invalidate any request parameters with confusing intent that might have unexpected results, such as defining both the `:q` free-form query parameter and at least one of the parameters of a structured query (`:city`, `:country`, etc.).
  """
  @moduledoc since: "1.0.0"

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
  @osm_detail_fields [:osmtype, :osmid]
  @endpoints [:search, :reverse, :status, :lookup, :details]

  @doc """
  Validates the content and intent of a request represented by a request parameters struct `params` (`%SearchParams{}`, `%ReverseParams{}`, etc.).

  You can use this function directly if you want to combine it with `ExNominatim.HTTP.prepare/3`.
  """
  def validate(params) when is_struct(params) do
    with %{valid?: true} = validated <- validate_all_fields(params),
         %{valid?: true} = verified <- verify_intent(validated) do
      {:ok, sanitize_comma_separated_strings(verified)}
    else
      %{valid?: false} = mi -> {:error, mi}
    end
  end

  defp validate_format_parameter(params) when is_struct(params) do
    k = :format
    d = ~w|xml json jsonv2 geojson geocodejson|

    valid_formats =
      case get_action(params) do
        :search -> d
        :reverse -> d
        :lookup -> d
        :details -> ~w|json|
        :status -> ~w|text json|
        _ -> []
      end

    if is_nil(params.format) or params.format in valid_formats,
      do: params,
      else: invalidate(params, k, explain(k))
  end

  defp get_action(params) when is_struct(params) do
    params
    |> Map.get(:__struct__)
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.split("_")
    |> hd()
    |> String.to_atom()
  end

  @doc """
  Sanitizes the values of those fields of the `params` request params struct (`%SearchParams{}`, `%ReverseParams{}`, etc.) that contain a comma-separated list of strings according to the Nominatim API specification. It collapses all spaces and trims and leading and trailing commas.

  You can use this function directly if you want to combine it with `ExNominatim.Validations.validate/1`.
  """
  def sanitize_comma_separated_strings(params) when is_struct(params) do
    [:layer, :countrycodes, :exclude_place_ids, :viewbox, :osm_ids]
    |> Enum.reduce(
      params,
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

  defp verify_intent_bifurcated_helper(m, single_field_a, multiple_fields_b, scope_b, message)
       when is_struct(m) and is_atom(single_field_a) and is_list(multiple_fields_b) and
              is_bitstring(message) do
    option_a = not is_nil(Map.get(m, single_field_a))

    option_b =
      m
      |> extract_values(multiple_fields_b)
      |> Enum.filter(&(!is_nil(&1)))
      |> all_some_or_none(multiple_fields_b)
      |> Kernel.in(scope_b)

    case {option_a, option_b} do
      {true, false} -> m
      {false, true} -> m
      {false, false} -> invalidate(m, :missing_query_params, message)
      {true, true} -> invalidate(m, :confusing_intent, message)
    end
  end

  defp all_some_or_none(fields, reference) do
    cond do
      fields == [] -> :none
      valid_number_value_ranged?(length(fields), :gtelt, mn: 1, mx: length(reference)) -> :some
      length(fields) == length(reference) -> :all
    end
  end

  defp verify_intent(%LookupParams{} = m) do
    osm_ids = Map.get(m, :osm_ids)
    if is_bitstring(osm_ids), do: m, else: invalidate(m, :missing_query_params, explain(:osm_ids))
  end

  defp verify_intent(%StatusParams{} = m), do: m

  defp verify_intent(%SearchParams{} = m) do
    verify_intent_bifurcated_helper(
      m,
      :q,
      @structured_query_fields,
      [:some, :all],
      "Must query either using freeform or structured query parameters"
    )
  end

  defp verify_intent(%DetailsParams{} = m) do
    verify_intent_bifurcated_helper(
      m,
      :place_id,
      @osm_detail_fields,
      [:all],
      "Must query either by osmtype, osmid and (optionally) class, or only by place_id"
    )
  end

  defp verify_intent(%ReverseParams{} = m) do
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

  defp invalidate(m, err_key, err_msg)
       when is_struct(m) and is_atom(err_key) and is_bitstring(err_msg) do
    %{m | valid?: false, errors: [{err_key, err_msg} | m.errors]}
  end

  defp extract_values(p, fields) when is_map(p) and is_list(fields) do
    Map.take(p, fields) |> Map.values()
  end

  defp validate_all_fields(m) when is_struct(m) do
    (permitted_keys(m) -- [:format])
    |> Enum.reduce(
      %{m | valid?: true, errors: []},
      fn k, acc ->
        case validate_field(k, acc) do
          {:ok, _} -> %{acc | valid?: acc.valid? and true}
          {:error, {err_key, err_msg}} -> invalidate(acc, err_key, err_msg)
        end
      end
    )
    |> validate_format_parameter()
  end

  defp validate_field(k, m) when is_atom(k) and is_map(m) do
    with {:permitted?, true} <- {:permitted?, k in permitted_keys(m)},
         {:valid?, {true, _}} <- {:valid?, valid?(Map.get(m, k), k)} do
      {:ok, m}
    else
      {:permitted?, false} -> {:error, {k, :invalid_key}}
      {:valid?, {false, message}} -> {:error, {k, message}}
    end
  end

  defp valid?(v, _) when is_nil(v), do: {true, nil}

  defp valid?(v, k) when k in [:lat, :lon, :polygon_threshold] do
    lim = limits(k)

    {
      number_or_its_string(v, :float) and valid_number_value_ranged?(v, lim[:crit], lim),
      explain(k)
    }
  end

  defp valid?(v, :osmtype = k) do
    message = explain(k)

    if is_bitstring(v) do
      {
        v in ["N", "W", "R"],
        message
      }
    else
      {false, message}
    end
  end

  defp valid?(v, :osmid = k) do
    {number_or_its_string(v, :integer), explain(k)}
  end

  defp valid?(v, bitstring_field)
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

  defp valid?(v, zero_one_field)
       when zero_one_field in [
              :addressdetails,
              :extratags,
              :namedetails,
              :bounded,
              :pretty,
              :keywords,
              :linkedplaces,
              :hierarchy,
              :group_hierarchy,
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

  defp valid?(v, :osm_ids = k) do
    message = explain(k)

    with true <- is_bitstring(v),
         true <- validate_osm_ids(v) do
      {true, message}
    else
      false -> {false, message}
    end
  end

  defp valid?(v, :format = k) do
    {
      v in ~w|xml json jsonv2 geojson geocodejson text|,
      explain(k)
    }
  end

  defp valid?(v, :featureType = k) do
    {
      v in ~w|country state city settlement|,
      explain(k)
    }
  end

  defp valid?(v, :layer = k) do
    layers = ~w|address poi railway natural manmade|

    {
      comma_separated_strings_to_list(v)
      |> Enum.map(fn x -> x in layers end)
      |> cumulative_and(),
      explain(k)
    }
  end

  defp valid?(v, :countrycodes = k) do
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

  defp valid?(v, :limit = k) do
    {
      is_integer(v) and valid_number_value_ranged?(v, :gtelte, mn: 1, mx: 40),
      explain(k)
    }
  end

  defp valid?(v, :zoom = k) do
    {
      is_integer(v) and
        valid_integer_value_discrete?(v, List.flatten([3, 5, 8, 10] ++ Enum.uniq(12..18))),
      explain(k)
    }
  end

  defp valid?(v, :email = k) do
    message = explain(k)
    regex = ~r/^[A-Za-z0-9._%+\-+']+@[A-Za-z0-9.-]+\.[A-Za-z]+$/

    if is_bitstring(v) do
      {
        Regex.match?(regex, v),
        message
      }
    else
      {false, message}
    end
  end

  defp valid?(v, :viewbox = k) do
    message = explain(k)
    # regex = ~r/\d*\.\d*/

    if is_bitstring(v) do
      {
        comma_separated_strings_to_list(v)
        |> Enum.with_index()
        |> Enum.map(fn {coord, idx} ->
          ctype = (Integer.mod(idx, 2) == 0 && :lon) || :lat
          valid?(coord, ctype) |> elem(0)
        end)
        |> cumulative_and(),
        message
      }
    else
      {false, message}
    end
  end

  defp valid?(v, :accept_language = k) do
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

  defp valid?(_, _), do: {true, nil}

  defp valid_integer_value_discrete?(v, valid_values \\ [0, 1])

  defp valid_integer_value_discrete?(v, valid_values)
       when is_integer(v) and is_list(valid_values) do
    v in valid_values
  end

  defp valid_integer_value_discrete?(v, valid_values) when is_bitstring(v) do
    {vi, _} = Integer.parse(v)
    valid_integer_value_discrete?(vi, valid_values)
  end

  defp valid_integer_value_discrete?(v, [0, 1]) when is_boolean(v) do
    true
  end

  defp valid_number_value_ranged?(v, crit, opts)
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

  defp valid_number_value_ranged?(v, crit, opts)
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

  defp valid_number_value_ranged?(v, crit, opts) when is_bitstring(v) do
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

  defp permitted_keys(m) when is_struct(m) do
    m |> Map.from_struct() |> Map.keys() |> Kernel.--([:valid?, :errors])
  end

  defp comma_separated_strings_to_list(v) when is_bitstring(v) do
    v
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end

  defp validate_osm_ids(osm_ids) when is_bitstring(osm_ids) do
    osm_ids
    |> comma_separated_strings_to_list()
    |> Enum.map(&validate_osm_id_single/1)
    |> cumulative_and()
  end

  defp validate_osm_id_single(osm_id) when is_bitstring(osm_id) do
    r = ~r/^[NWR]\d+$/
    Regex.match?(r, osm_id)
  end

  defp cumulative_and(list) when is_list(list) do
    Enum.reduce(list, true, fn x, acc -> x and acc end)
  end

  defp nonempty_string?(s) do
    is_bitstring(s) and s != ""
  end

  defp number_or_its_string(v, type) when is_bitstring(v) and type in [:integer, :float] do
    with {_vi, ri} <- Integer.parse(v) do
      cond do
        type == :integer and ri == "" -> true
        type == :float and ri != "" -> true
        true -> false
      end
    else
      :error -> false
    end
  end

  defp number_or_its_string(v, type) when is_number(v) and type in [:integer, :float] do
    is_this_type = apply(Kernel, to_guard(type), [v])

    case {is_integer(v), is_float(v)} do
      {true, false} -> true and is_this_type
      {false, true} -> true and is_this_type
      {false, false} -> false
    end
  end

  defp action_to_struct(action) when action in @endpoints do
    [
      "ExNominatim.Client",
      action |> to_string |> Kernel.<>("_params") |> Macro.camelize() |> String.to_atom()
    ]
    |> Module.safe_concat()
    |> struct()
  end

  defp to_guard(atom) when is_atom(atom) do
    ["is_", atom |> to_string]
    |> List.to_string()
    |> String.to_atom()
  end

  defp collapse_spaces(s) when is_bitstring(s) do
    s
    |> String.split(" ")
    |> Enum.reject(&(&1 == ""))
    |> List.to_string()
  end

  defp limits(:lat), do: [mn: -90.0, mx: 90.0, crit: :gtelte, type: :float]
  defp limits(:lon), do: [mn: -180.0, mx: 180.0, crit: :gtelt, type: :float]
  defp limits(:polygon_threshold), do: [mn: -1000.0, mx: 1000.0, crit: :gtlt, type: :float]

  defp explain(k) when is_atom(k) and k not in @endpoints do
    Map.get(explain_fields(), k)
  end

  @doc """
  Show all fields and their explanations.
  """
  def explain_fields do
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
      addressdetails: "Include a breakdown of the address into elements" <> default(0, :bool),
      extratags:
        "Include any additional information in the result that is available in the database" <>
          default(0, :bool),
      namedetails: "Include a full list of names for the result" <> default(0, :bool),
      accept_language:
        "Browser language string consisting of ISO 639-1 Set 1 codes" <>
          default("content of Accept-Language HTTP header"),
      countrycodes: "Comma-separated list of ISO 3166-1 alpha-2 country codes" <> default(),
      layer:
        "Comma-separated list of: address, poi, railway, natural, manmade" <>
          default() <> " (no restriction)",
      featureType: "One of: country, state, city, settlement" <> default(),
      exclude_place_ids: "Comma-separated list of place_id items to skip" <> default(),
      pretty: "Add indentation to the output to make it more human-readable" <> default(0, :bool),
      keywords:
        "Include a list of name keywords and address keywords in the result" <> default(0, :bool),
      linkedplaces:
        "Include details of places that are linked with this one" <> default(1, :bool),
      hierarchy: "Include details of places lower in the address hierarchy" <> default(0, :bool),
      group_hierarchy: "Group output of the address hierarchy by type" <> default(0, :bool),
      viewbox:
        "Boost parameter which focuses the search on the given area. <x1>,<y1>,<x2>,<y2> where x is longitude and y is latitude" <>
          default(),
      bounded: "Exclude any results outside the viewbox" <> zero_or_one() <> default(0),
      polygon_geojson: polygon_output_message("GeoJSON"),
      polygon_kml: polygon_output_message("KML"),
      polygon_svg: polygon_output_message("SVG"),
      polygon_text: polygon_output_message("text"),
      polygon_threshold:
        "Tolerance in degrees with which the simplified geometry may differ from the original geometry, floating-point number" <>
          default(0.0),
      email: "Valid email address (if making a large number of requests)" <> default(),
      dedupe: "Toggle the deduplication mechanism" <> default(1, :bool),
      debug: "Output assorted developer debug information in HTML" <> default(0, :bool),
      lat: "Floating-point number in range [-90, 90] (or its string representation)",
      lon: "Floating-point number in range [-180, 180) (or its string representation)",
      zoom: "Level of detail required for the address [3, 5, 8, 10, 12..18]" <> default(18),
      osmtype: "Type of OSM object, one of N (node), W (way), or R (relation)",
      osmid: "OSM ID of the object, integer",
      class:
        "Optional OSM tag to distinguish between entries, when the corresponding OSM object has more than one main tag",
      osm_ids:
        "Comma-separated list of up to 50 OSM ids each prefixed with its type, one of node(N), way(W) or relation(R).",
      format:
        "One of: xml, json, jsonv2, geojson, geocodejson, text (Default: jsonv2 for /search, xml for /reverse, text only for /status)"
    }
  end

  @doc """
  Given a request params struct (`%ReverseParams{}`, `%SearchParams{}`, etc.), a keyword list, or a list of atoms corresponding to keys, explain the fields, their default values (if any) and their values' limits (if applicable). It ignores any keyword list keys or atoms in the list that do not correspond to request parameters. If provided with the atom of a field, it returns the validation/explanation message for that field
  """
  def explain_fields(x)
      when is_struct(x) or is_list(x) or (is_atom(x) and x in @endpoints) do
    cond do
      is_struct(x) -> permitted_keys(x)
      is_list(x) and Keyword.keyword?(x) -> Keyword.keys(x)
      is_list(x) -> x
      is_atom(x) -> x |> action_to_struct() |> permitted_keys()
    end
    |> then(&Map.take(explain_fields(), &1))
  end

  def explain_fields(x) when is_atom(x) and x not in @endpoints do
    explain(x)
  end

  defp polygon_output_message(format) when is_bitstring(format) do
    "Polygon output in " <> format <> zero_or_one() <> default(0)
  end

  defp default, do: default("unset")

  defp default(v) when is_bitstring(v) do
    " (Default: " <> v <> ")"
  end

  defp default(v) when is_number(v), do: default(to_string(v))

  defp default(v, :bool) when v == 0 or v == 1 do
    zero_or_one() <> default(to_string(v) <> " or " <> int_to_bool(v))
  end

  defp int_to_bool(v) when v == 0 or v == 1 do
    to_string((v == 1 && true) || false)
  end

  defp zero_or_one, do: ", 0 or 1 (or boolean false/true)"
end
