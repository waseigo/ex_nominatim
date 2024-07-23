defmodule ExNominatim.Validations do
  alias ExNominatim.SearchParams

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

  def validate(m) when is_map(m) do
    permitted_keys(m)
    |> Enum.reduce_while(
      {:ok, m},
      fn k, acc ->
        case validate_field(k, m) do
          {:ok, _} -> {:cont, acc}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end
    )
  end

  def validate_field(k, m) when is_atom(k) and is_map(m) do
    with {:permitted?, true} <- {:permitted?, k in permitted_keys(m)},
         {:valid?, {true, _}} <- {:valid?, valid?(Map.get(m, k), k)} do
      {:ok, m}
    else
      {:permitted?, false} -> {:error, :invalid_key}
      {:valid?, {false, message}} -> {:error, {k, message}}
    end
  end

  def valid?(v, _) when is_nil(v), do: {true, nil}

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
    message = "String to search for (non-empty)"

    cond do
      is_nonempty_string?(v) -> {true, message}
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
    message = "0 or 1"
    {valid_integer_value_discrete?(v), message}
  end

  def valid?(v, :format) do
    {
      v in ~w|xml json jsonv2 geojson geocodejson|,
      "One of: xml, json, jsonv2, geojson, geocodejson (Default: jsonv2)"
    }
  end

  def valid?(v, :featureType) do
    {
      v in ~w|country state city settlement|,
      "One of: country, state, city, settlement (Default: unset)"
    }
  end

  def valid?(v, :layer) do
    layers = ~w|address poi railway natural manmade|

    {
      comma_separated_strings_to_list(v)
      |> Enum.map(fn x -> x in layers end)
      |> cumulative_and(),
      "Comma-separated list of: address, poi, railway, natural, manmade (Default: unset (no restriction))"
    }
  end

  def valid?(v, :countrycodes) do
    message = "Comma-separated list of ISO 3166-1 alpha-2 country codes (Default: unset)"

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

  def valid?(v, :limit) do
    {
      valid_integer_value_ranged?(v, :gtlte),
      "Cannot be more than 40 (Default: 10)"
    }
  end

  def valid?(v, :polygon_threshold) do
    message = "Floating-point number (Default: 0.0)"

    cond do
      is_float(v) ->
        {true, message}

      is_bitstring(v) ->
        {vf, _} = Float.parse(v)
        valid?(vf, :polygon_threshold)

      true ->
        {false, message}
    end
  end

  def valid?(v, :email) do
    message = "Valid email address (Default: unset)"

    if is_bitstring(v) do
      {
        Regex.match?(~r/^[A-Za-z0-9._%+\-+']+@[A-Za-z0-9.-]+\.[A-Za-z]+$/, v),
        message
      }
    else
      {false, message}
    end
  end

  def valid?(v, :accept_language) do
    message =
      "Browser language string consisting of ISO 639-1 Set 1 codes (Default: content of \"Accept-Language\" HTTP header)"

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

  def valid_integer_value_discrete?(v, valid_values \\ [0, 1])

  def valid_integer_value_discrete?(v, valid_values)
      when is_integer(v) and is_list(valid_values) do
    v in valid_values
  end

  def valid_integer_value_discrete?(v, valid_values) when is_bitstring(v) do
    {vi, _} = Integer.parse(v)
    valid_integer_value_discrete?(vi, valid_values)
  end

  def valid_integer_value_ranged?(v, crit, opts \\ [mn: 0, mx: 40])

  def valid_integer_value_ranged?(v, crit, opts)
      when is_integer(v) and is_list(opts) and
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

  def valid_integer_value_ranged?(v, crit, opts)
      when is_integer(v) and is_list(opts) and
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

  def valid_integer_value_ranged?(v, crit, opts) when is_bitstring(v) do
    {vi, _} = Integer.parse(v)
    valid_integer_value_ranged?(vi, crit, opts)
  end

  def permitted_keys(m) when is_struct(m) do
    m |> Map.from_struct() |> Map.keys()
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

  def sanitize_comma_separated_strings(%SearchParams{} = query) do
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

  def is_nonempty_string?(s) do
    is_bitstring(s) and s != ""
  end

  def collapse_spaces(s) when is_bitstring(s) do
    s
    |> String.split(" ")
    |> Enum.reject(&(&1 == ""))
    |> List.to_string()
  end
end
