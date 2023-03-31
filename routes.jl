using LinearAlgebra, StatsBase, XGBoost, CSV, DataFrames, Dates
using Statistics: median, mean
using Genie, Genie.Router
using Genie.Renderer, Genie.Renderer.Html, Genie.Renderer.Json, Genie.Requests
using JSONTables

Genie.config.run_as_server = true
Genie.config.cors_headers["Access-Control-Allow-Origin"] = "*"
# This has to be this way - you should not include ".../"
Genie.config.cors_headers["Access-Control-Allow-Headers"] = "Content-Type"
Genie.config.cors_headers["Access-Control-Allow-Methods"] = "GET,POST,PUT,DELETE,OPTIONS"
Genie.config.cors_allowed_origins = ["*"]

zipdf = CSV.File("./uszips3.csv")|>DataFrame
zll = zipdf[!,[:city,:state_id,:zip,:latitude,:longitude]]
dryvan_predictions_df = CSV.File("./dryvan_preds.csv")|>DataFrame
reefer_predictions_df = CSV.File("./reefer_preds.csv")|>DataFrame
flatbed_predictions_df = CSV.File("./flatbed_preds.csv")|>DataFrame
dryvan_pred = dryvan_predictions_df[!,[:Date,:OriginCity,:OriginState,:OriginZip,:DestinationCity,:DestinationState,:DestinationZip,:Distance,:EquipmentType,:LowSpot,:MedianSpot,:HighSpot,:SpotDeviation,:OriginLatitude,:OriginLongitude,:DestinationLatitude,:DestinationLongitude]]
reefer_pred = reefer_predictions_df[!,[:Date,:OriginCity,:OriginState,:OriginZip,:DestinationCity,:DestinationState,:DestinationZip,:Distance,:EquipmentType,:LowSpot,:MedianSpot,:HighSpot,:SpotDeviation,:OriginLatitude,:OriginLongitude,:DestinationLatitude,:DestinationLongitude]]
flatbed_pred = flatbed_predictions_df[!,[:Date,:OriginCity,:OriginState,:OriginZip,:DestinationCity,:DestinationState,:DestinationZip,:Distance,:EquipmentType,:LowSpot,:MedianSpot,:HighSpot,:SpotDeviation,:OriginLatitude,:OriginLongitude,:DestinationLatitude,:DestinationLongitude]]

function getApproximateDistance(lat1, long1, lat2, long2)
  D2 = (111 * (lat1-lat2))^2 + (85 * (long1-long2))^2
  #=
  The distance of one degree latitude is approximately 111 kilometers (constant around the earth)
  The distance of one degree longitude in the center of the contiguous USA (Lebanon, Kansas)
  is approximately 85 kilometers.
  We're using kilometers since we'll use a weighted average later.  The weights will be
  1/(1+D) and the 1 in the denominator will have less effect for longer distances, so we use kilometers
  =#
  D = sqrt(D2)
  return D
end 

route("/hello", method=POST) do
  raw = jsonpayload()
  if raw["equipment_type"] == "dryvan"
    p_df = copy(dryvan_pred)
  elseif raw["equipment_type"] == "reefer"
    p_df = copy(reefer_pred)
  elseif raw["equipment_type"] == "flatbed"
    p_df = copy(flatbed_pred)
  end
  marketzipsin = unique(p_df[!,:OriginZip])
  outbounddf = filter(row -> row[:zip] in marketzipsin, zll)
  origin_df = filter(row -> row[:zip] == raw["origin_zip"],zll)
  olat,olong = origin_df[1,[:latitude,:longitude]]
  odistances = getApproximateDistance.(olat,olong,outbounddf[!,:latitude],outbounddf[!,:longitude])
  insertcols!(outbounddf,6,:DistanceToOrigin => odistances)
  outbounddf = sort(outbounddf,:DistanceToOrigin)
  top3marketsin = outbounddf[1:3,:zip]
  outboundpredictions = filter(row -> row[:OriginZip] in top3marketsin, p_df)

  marketzipsout = unique(outboundpredictions[!,:DestinationZip])
  inbounddf = filter(row -> row[:zip] in marketzipsout, zll)
  destination_df = filter(row -> row[:zip] == raw["destination_zip"],zll)
  dlat,dlong = destination_df[1,[:latitude,:longitude]]
  ddistances = getApproximateDistance.(dlat,dlong,inbounddf[!,:latitude],inbounddf[!,:longitude])
  insertcols!(inbounddf,6,:DistanceToDestination => ddistances)
  inbounddf = sort(inbounddf,:DistanceToDestination)
  top3marketsout = inbounddf[1:3,:zip]
  inboundpredictions = filter(row -> row[:DestinationZip] in top3marketsout, outboundpredictions)

  r,c = size(inboundpredictions)
  m_origin_df = filter(row -> row[:zip] == raw["origin_zip"],zll)
  molat,molong = m_origin_df[1,[:latitude,:longitude]]
  m_destination_df = filter(row -> row[:zip] == raw["destination_zip"],zll)
  mdlat,mdlong = m_destination_df[1,[:latitude,:longitude]]
  modistances = getApproximateDistance.(molat,molong,inboundpredictions[!,:OriginLatitude],inboundpredictions[!,:OriginLongitude])
  insertcols!(inboundpredictions,c+1,:DistanceToOrigin => modistances)
  mddistances = getApproximateDistance.(mdlat,mdlong,inboundpredictions[!,:DestinationLatitude],inboundpredictions[!,:DestinationLongitude])
  insertcols!(inboundpredictions,c+2,:DistanceToDestination => mddistances)
  weights = (1 .+ modistances).^-2 .* (1 .+ mddistances).^-2
  insertcols!(inboundpredictions, c+3, :Weights => weights)
  weightedMinPrice = (inboundpredictions[!,:LowSpot]'*weights)/sum(weights)
  weightedMedianPrice = (inboundpredictions[!,:MedianSpot]'*weights)/sum(weights)
  weightedMaxPrice = (inboundpredictions[!,:HighSpot]'*weights)/sum(weights)
  weightedDev = (inboundpredictions[!,:SpotDeviation]'*weights)/sum(weights)
  return json(Dict("Min" => round(weightedMinPrice,digits=2),"Median" => round(weightedMedianPrice,digits=2),"Max" => round(weightedMaxPrice,digits=2)))
end
