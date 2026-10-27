[out:json][timeout:180];
way[ref~"(N35|A35)"][highway~"^(motorway|trunk|primary)$"](52.18,6.2,52.45,6.95)->.r;
(
 node(around.r:40)[highway=traffic_signals];
 way(around.r:3)[highway~"^(primary|secondary|tertiary|unclassified|residential|service|trunk_link|primary_link|motorway_link|track|cycleway)$"];
 way(around.r:40)[railway~"^(rail|light_rail)$"];
 way(around.r:20)[junction=roundabout];
);
out tags geom;
