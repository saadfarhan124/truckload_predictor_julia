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
predictions_df = CSV.File("./preds.csv")|>DataFrame
pred = predictions_df[!,[:Date,:OriginCity,:OriginState,:OriginZip,:DestinationCity,:DestinationState,:DestinationZip,:Distance,:EquipmentType,:LowSpot,:MedianSpot,:HighSpot,:SpotDeviation,:OriginLatitude,:OriginLongitude,:DestinationLatitude,:DestinationLongitude]]

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

  p_df = copy(pred)
  r,c = size(p_df)
  origin_df = filter(row -> row[:zip] == raw["origin_zip"],zll)
  olat,olong = origin_df[1,[:latitude,:longitude]]
  destination_df = filter(row -> row[:zip] == raw["destination_zip"],zll)
  dlat,dlong = destination_df[1,[:latitude,:longitude]]

  odistances = getApproximateDistance.(olat,olong,p_df[!,:OriginLatitude],p_df[!,:OriginLongitude])
  insertcols!(p_df,c+1,:DistanceToOrigin => odistances)
  ddistances = getApproximateDistance.(dlat,dlong,p_df[!,:DestinationLatitude],p_df[!,:DestinationLongitude])
  insertcols!(p_df,c+2,:DistanceToDestination => ddistances)
  weights = (1 .+ odistances).^-2 .* (1 .+ ddistances).^-2
  insertcols!(p_df, c+3, :Weights => weights)
  weightedMinPrice = (p_df[!,:LowSpot]'*weights)/sum(weights)
  weightedMedianPrice = (p_df[!,:MedianSpot]'*weights)/sum(weights)
  weightedMaxPrice = (p_df[!,:HighSpot]'*weights)/sum(weights)
  weightedDev = (p_df[!,:SpotDeviation]'*weights)/sum(weights)

  return json(Dict("Min":round(weightedMinPrice,digits=2),"Median":round(weightedMedianPrice,digits=2),"Max":round(weightedMaxPrice,digits=2)))

end




