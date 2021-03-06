#==============================================================================
#
# 04_select.r -- select "informative" Twitter users
#
# The script selects users with 25+ followers and 100+ tweets who tweeted in the
# last six months and who could be located in France based on their location
# field. All users are saved to data/users.csv.
#
# The adjacency matrix that is sent to the first stage of the model further
# restricts users to those following at least 10 politicians, and politicians
# to those followed by at least 200 "informative" users. The result is saved to
# model/matrix_selected.rda, with the starting values for that subsample.
#
#==============================================================================

source("00_functions.r")

library(dplyr)
library(readr)
library(stringr)

u = read_csv("data/users.csv", col_types = list(id = col_character()))

cat(date(), ": parsing", nrow(u), "users...\n")

#==============================================================================
# SELECT ACTIVE USERS
#==============================================================================

cat("-", round(100 * sum(u$followers >= 25) / nrow(u), 1),
    "% of users have 25+ followers\n")

cat("-", round(100 * sum(u$statuses >= 100) / nrow(u), 1),
    "% of users have 100+ statuses\n")

# six months since first round of last local elections (April 22, 2015)
cat("-", round(100 * sum(u$last_tweeted >= as.Date("2014-09-22"), na.rm = TRUE) / nrow(u), 1),
    "% of users have tweeted in the last six months\n")

u$active = with(u, followers >= 25 & statuses >= 100 & last_tweeted >= as.Date("2014-09-22"))
# table(u$active, exclude = NULL)

cat("-", round(100 * sum(u$active, na.rm = TRUE) / nrow(u), 1),
    "% of users match all activity criteria\n")

#==============================================================================
# SELECT USERS LOCATED IN FRANCE
#==============================================================================

cat(date(), ": locating users...\n")

# clean up location strings
locs = gsub("[[:punct:]]|[0-9]", " ", u$location) # unwanted symbols
locs = iconv(locs, to = "ASCII//TRANSLIT")        # accents to punctuation
locs = gsub("[[:punct:]]", "", locs)              # accents out
locs = tolower(str_trim(gsub("\\s+", " ", locs))) # spaces out

# replacements, mostly to match region names
locs[ locs %in% c("", "world", "monde") ] = NA
locs[ locs %in% c("dom tom", "fr", "fra", "france fr") ] = "france"
locs[ locs == "idf" ] = "ile de france"
locs[ locs %in% c("midi", "pyrenees") ] = "midi pyrenees"
locs[ locs %in% c("paca", "provence", "cote d azur") ] = "provence alpes cote d azur"
locs[ locs %in% c("poitou", "charentes") ] = "poitou charentes"

# choose randomly to match region name (probabilities relative to census population 2006)
locs[ locs == "normandie" ] = sample(c("basse normandie", "haute normandie"), 1, prob = c(.44, .56))

# départements, with population figures for entire département
# https://fr.wikipedia.org/wiki/Liste_des_pr%C3%A9fectures_de_France
# https://fr.wikipedia.org/wiki/Liste_des_départements_français_classés_par_population_et_superficie
geo = read_csv("data/geo_departements.csv")

regex = na.omit(geo$departement)
regex = regex[ order(-nchar(regex)) ] # longest first (avoid partial matches)
regex = gsub("[[:punct:]]|[0-9]", " ", regex[ regex != "" ])
regex = iconv(regex, to = "ASCII//TRANSLIT")
regex = unique(gsub("[[:punct:]]", "", regex)) # n = 101
regex = paste0("^", regex, "$|^", regex, "\\s|\\s", regex, "$|\\s", regex, "\\s")
regex = tolower(paste0(regex, collapse = "|"))
u$departement = str_trim(str_extract(locs, regex))

cat("-", round(100 * sum(!is.na(u$departement)) / nrow(u), 1),
    "% of users located in a French département\n")

# préfectures et sous-préfectures 2014 (inclut les chefs-lieu régionaux)
regex = c(geo$prefecture, unlist(strsplit(geo$sousprefs, ",")))

# villes de 30 000+ habitants (Insee 2012/2014)
# https://fr.wikipedia.org/wiki/Liste_des_communes_de_France_les_plus_peupl%C3%A9es
geo = read_csv("data/geo_villes.csv")
regex = c(regex, geo$ville)

# cleaning up
regex = na.omit(regex)
regex = regex[ order(-nchar(regex)) ] # longest first (avoid partial matches)
regex = gsub("[[:punct:]]|[0-9]", " ", regex[ regex != "" ])
regex = iconv(regex, to = "ASCII//TRANSLIT")
regex = unique(gsub("[[:punct:]]", "", regex)) # n = 480

# # this one is too long to fit in one shot, causes a C error
# u$ville = str_trim(str_extract(locs, regex))

# pass each part of the regex separately
v1 = tolower(paste0(paste0("^", regex, "$"), collapse = "|"))
v1 = str_trim(str_extract(locs, v1))
v2 = tolower(paste0(paste0("^", regex, "\\s"), collapse = "|"))
v2 = str_trim(str_extract(locs, v2))
v3 = tolower(paste0(paste0("\\s", regex, "$"), collapse = "|"))
v3 = str_trim(str_extract(locs, v3))
v4 = tolower(paste0(paste0("\\s", regex, "\\s"), collapse = "|"))
v4 = str_trim(str_extract(locs, v4))

# bind all results and select one randomly in case of multiple results
vv = cbind(v1, v2, v3, v4)
vv = apply(vv, 1, function(x) ifelse(all(is.na(x)), NA, sample(na.omit(x), 1)))
u$ville = vv

# Canadian homonym
u$ville[ u$ville == "laval" & grepl("canada|qu(é|e)bec|qc", u$location, ignore.case = TRUE) ] = NA

# other possible exceptions (not exhaustive)
# Algérie|Belgique|Canada|Congo|Mali|Maroc|Qu(e|é)bec|Sénégal|Suisse|Tunisie|Togo

cat("-", round(100 * sum(!is.na(u$ville)) / nrow(u), 1),
    "% of users located in a French city\n")

# régions
regex = c("Mayotte", na.omit(unique(geo$region))) # n = 28 (one blank)
regex = regex[ order(-nchar(regex)) ] # longest first (avoid partial matches)
regex = gsub("[[:punct:]]|[0-9]", " ", regex[ regex != "" ])
regex = iconv(regex, to = "ASCII//TRANSLIT")
regex = unique(gsub("[[:punct:]]", "", regex)) # n = 27
regex = paste0("^", regex, "$|^", regex, "\\s|\\s", regex, "$|\\s", regex, "\\s")
regex = tolower(paste0(regex, collapse = "|"))
u$region = str_trim(str_extract(locs, regex))

cat("-", round(100 * sum(!is.na(u$region)) / nrow(u), 1),
    "% of users located in a French region\n")

# France
u$france = str_detect(locs, "^france$|^france\\s|\\sfrance$|\\sfrance\\s")

cat("-", round(100 * sum(u$france, na.rm = TRUE) / nrow(u), 1),
    "% of users located in France\n")

# sample active users who mention France or any French geographical location
u$located = isTRUE(u$france) | !is.na(u$departement) | !is.na(u$region) | !is.na(u$ville)

cat("-", round(100 * sum(u$located) / nrow(u), 1),
    "% of users located somewhere inside of France\n")

cat("-", round(100 * sum(!u$located & !is.na(u$location)) / nrow(u), 1),
    "% of users located somewhere outside of France\n")

cat("-", round(100 * sum(is.na(u$location)) / nrow(u), 1),
    "% of users with no location at all\n")

# final sample: active and located users
u$sample = u$active & u$located

# discards users with no most recent tweet
u$sample[ is.na(u$sample) ] = FALSE

#==============================================================================
# GENDERIZE USERS
#==============================================================================

cat(date(), ": gendering users...\n")

# fichier des prénoms
# Source: https://www.data.gouv.fr/fr/datasets/liste-de-prenoms/
pre = read_csv("data/prenoms.csv")

# remove dashes and accents
pre$prenom = gsub("-", "", pre$prenom)
pre$prenom = iconv(pre$prenom, to = "ASCII//TRANSLIT")
pre$prenom = gsub("[[:punct:]]", "", pre$prenom)

# find duplicates
pre = unique(pre[, c("prenom", "genre") ])

# get rid of duplicates
# filter(pre, prenom %in% pre$prenom[ duplicated(pre$prenom) ])
pre = filter(pre, !(prenom %in% c("asa", "celestine", "daniele", "irene", "michele") & genre == "m"))

# vector of names
name = tolower(gsub("[[:punct:]]|[0-9]", "", u$name))
name = stringi::stri_enc_toutf8(name, validate = TRUE)
name = str_trim(gsub("\\s+", " ", name))
name = iconv(name, to = "ASCII//TRANSLIT")
name = gsub("[[:punct:]]", "", name)

# vector of first names
prenoms = pre$genre
names(prenoms) = pre$prenom

# extract first word
name = sapply(name, function(x) unlist(strsplit(x, "\\s"))[1])
name[ !name %in% names(prenoms) ] = NA

# match first names and assign gender
name = prenoms[ name ]
u$gender = ifelse(name %in% c("m", "f"), name, NA)

cat("-", round(100 * sum(!is.na(u$gender)) / nrow(u), 1),
    "% of users assigned a gender\n")

cat("-", round(100 * sum(u$gender == "m", na.rm = TRUE) / nrow(u), 1),
    "% of users are males\n")

cat("-", round(100 * sum(u$gender == "f", na.rm = TRUE) / nrow(u), 1),
    "% of users are females\n")

cat("- male-to-female ratio:",
    round(sum(u$gender == "m", na.rm = TRUE) / sum(u$gender == "f", na.rm = TRUE), 1),
    "\n")

# save all users
write_csv(u, "data/users.csv")

#==============================================================================
# GENDER RATIOS
#==============================================================================

# load politicians
d = read_csv("data/politicians.csv", col_types = list(id = col_character()))

if(!file.exists("data/gender_ratios.csv")) {

  # load lists of followers
  load("model/userlist.rda")

  gnd = data.frame()
  for(i in 1:length(followers_m)) {

    f = followers_m[[ i ]]
    g = u$gender[ which(u$id %in% f) ]
    s = u$gender[ which(u$id[ u$sample ] %in% f) ]

    gnd = rbind(gnd, data.frame(
      twitter = gsub("followers/|\\.rda", "", filesList[ i ]),
      followers = length(f),
      users = length(g),
      gendered = length(na.omit(g)),
      males = sum(na.omit(g) == "m"),
      females = sum(na.omit(g) == "f"),
      sample = length(s),
      gendered_sample = length(na.omit(s)),
      males_sample = sum(na.omit(s) == "m"),
      females_sample = sum(na.omit(s) == "f"),
      stringsAsFactors = FALSE))

  }

  gnd$ratio = gnd$males / gnd$females
  gnd$ratio_sample = gnd$males_sample / gnd$females_sample
  gnd = left_join(select(d, twitter, gender, party), gnd, by = "twitter")

  write_csv(gnd, "data/gender_ratios.csv")

}

gnd = read_csv("data/gender_ratios.csv")
gnd = filter(gnd, !is.infinite(ratio), !is.infinite(ratio_sample))

# average gender ratios
round(mean(gnd$ratio, na.rm = TRUE), 2)
round(mean(gnd$ratio_sample, na.rm = TRUE), 2)

# gender ratios of male politicians
round(mean(gnd$ratio[ gnd$gender == "m" ], na.rm = TRUE), 2)
round(mean(gnd$ratio_sample[ gnd$gender == "m" ], na.rm = TRUE), 2)

# gender ratios of female politicians
round(mean(gnd$ratio[ gnd$gender == "f" ], na.rm = TRUE), 2)
round(mean(gnd$ratio_sample[ gnd$gender == "f" ], na.rm = TRUE), 2)

# t-tests
t.test(gnd$ratio[ gnd$gender == "m" ], gnd$ratio[ gnd$gender == "f" ])
t.test(gnd$ratio_sample[ gnd$gender == "m" ], gnd$ratio_sample[ gnd$gender == "f" ])

#==============================================================================
# SELECT "INFORMATIVE" USERS
#==============================================================================

cat(date(), ": selecting users...\n")

load("model/matrix.rda")
load("model/startingvalues.rda")

# sanity checks
stopifnot(!is.na(u$id) & !duplicated(u$id))
stopifnot(u$id %in% rownames(y))

# subsample 0: find selected users in matrix
stopifnot(as.character(na.omit(u$id[ u$sample ])) %in% rownames(y))
y = y[ rownames(y) %in% as.character(na.omit(u$id[ u$sample ])), ]

stopifnot(sum(u$sample, na.rm = TRUE) == nrow(y))
cat("- selected", nrow(y), "active users in France:\n")

# subsample 1: ignore politicians with no recent tweets
cat("  - removing", sum(!d$statuses | d$last_tweeted < as.Date("2014-09-22"), na.rm = TRUE),
    "inactive politicians\n")

d = filter(d, statuses > 0 & last_tweeted >= as.Date("2014-09-22"))

y = y[, colnames(y) %in% d$twitter ]
start.phi = start.phi[ names(start.phi) %in% d$twitter ]

# subsample 2: "informative" users who follow 10+ politicians
cat("  -", sum(rowSums(y) >= 10), "follow 10+ of", ncol(y), "politicians\n")
y = y[ rowSums(y) >= 10, ]

# subsample 3: politicians followed by 200+ of these users
cat("  -", sum(colSums(y) >= 200), "politicians followed by 200+ of these\n")
start.phi = start.phi[ colSums(y) >= 200 ]
y = y[ , colSums(y) >= 200 ]

cat("\nSampled politicians:\n\n")
cat(" ", paste0(head(colnames(y)), collapse = ", "), "...\n")
cat("  ...", paste0(tail(colnames(y)), collapse = ", "), "\n")

cat("\nSampled parties:\n")
print(table(d$party[ d$twitter %in% colnames(y) ]))

# (re)load politicians and their followers lists
d = read_csv("data/politicians.csv", col_types = list(id = col_character()))

cat("\nPercentages of full sample:\n")
print(100 * table(d$party[ d$twitter %in% colnames(y) ]) / table(d$party), digits = 1)

cat("\nSampled mandates:\n")
print(table(d$type[ d$twitter %in% colnames(y) ]))

cat("\nPercentages of full sample:\n")
print(100 * table(d$type[ d$twitter %in% colnames(y) ]) / table(d$type), digits = 1)

# sanity checks
stopifnot(colnames(y) == names(start.phi))
stopifnot(ncol(y) == length(start.phi))

save(y, start.phi, file = "model/matrix_selected.rda")

d$sample = d$twitter %in% colnames(y)

write_csv(d, "data/politicians.csv")

cat(date(), ": done.\n")

rm(list = ls())
gc()
