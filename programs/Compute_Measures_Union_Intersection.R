rm(list=ls())
library(cttools)
library(fslr)
library(oro.dicom)
library(bitops)
library(arules)
library(plyr)
options(matlab.path='/Applications/MATLAB_R2014b.app/bin')

# username <- Sys.info()["user"][[1]]
rootdir = path.expand("~/Dropbox/CTR/DHanley/CT_Registration")

ROIformat = TRUE
study = "Original_Images"
if (ROIformat) {
  study = "AM_ROI_images"
}

basedir = file.path(rootdir, "Final_Brain_Seg")
resdir = file.path(basedir, "results")
homedir <- file.path(basedir, study)
#basedir <- file.path("/Volumes/CT_Data/MISTIE")

setwd(homedir)

ids = list.dirs(homedir, recursive=FALSE, full.names=FALSE)
ids = basename(ids)
ids = grep("\\d\\d\\d-(\\d|)\\d\\d\\d", ids, value=TRUE)
length(ids)

iid = 1

sdir = file.path(rootdir, "Final_Brain_Seg", "Original_Images")

imgs = list.files(sdir, pattern = "\\.nii\\.gz", recursive=TRUE,
                  full.names=TRUE)
imgs = imgs[ !grepl("dcm2nii", imgs)]
imgs = imgs[ !grepl("Skull_Stripped", imgs)]

img.df = data.frame(img=imgs, stringsAsFactors=FALSE)
img.df$id = basename(img.df$img)
ss = strsplit(img.df$id, "_")
img.df$id = sapply(ss, function(x) {
  paste(x[1:4], collapse="_", sep="")
})


ss.imgs = list.files(sdir, pattern = "\\.nii\\.gz", recursive=TRUE,
                     full.names=TRUE)
ss.imgs = ss.imgs[ grepl("Skull_Stripped", ss.imgs)]
ss.imgs = ss.imgs[ grepl("[M|m]ask", ss.imgs)]
ss.imgs = ss.imgs[ !grepl("refill", ss.imgs)]

ss.df = data.frame(ssimg=ss.imgs, stringsAsFactors=FALSE)
ss = strsplit(ss.df$ssimg, "_SS")
ss = sapply(ss, `[`, 1)
dn = dirname(dirname(ss))
bn = basename(ss)
ss = file.path(dn, paste0(bn, ".nii.gz"))
ss.df$img = ss

img.df$check = 1
ssdf = merge(ss.df, img.df, all.x=TRUE)
img.df$check = NULL

stopifnot(!any(is.na(ssdf$id)))
stopifnot(!any(is.na(ssdf$id)))
stopifnot(!any(is.na(ssdf$check)))
ssdf$check = NULL

roidir = file.path(rootdir, "Final_Brain_Seg", "AM_ROI_Images")

rimgs = list.files(roidir, pattern = "\\.nii\\.gz", recursive=TRUE,
                   full.names=TRUE)
rimgs = rimgs[ !grepl("dcm2nii", rimgs)]
rimgs = rimgs[ !grepl("Skull_Stripped", rimgs)]

rimg.df = data.frame(rimg=rimgs, stringsAsFactors=FALSE)
rimg.df$id = basename(rimg.df$rimg)
ss = strsplit(rimg.df$id, "_")
rimg.df$id = sapply(ss, function(x) {
  paste(x[1:4], collapse="_", sep="")
})

df = merge(rimg.df, img.df, all.x=TRUE)

df = merge(df, ssdf, all.x=TRUE)

df$hdr = file.path(dirname(df$img), "Sorted", 
                   paste0(nii.stub(df$img, bn=TRUE), "_Header_Info.Rda"))
df$pid = sapply(strsplit(df$id, "_"), `[`, 1)


######################
# Keeping only one scan per person
######################
df = ddply(df, .(pid), function(x){
  x = x[ x$id == x$id[1], ]
  x
})

n.pid = length(unique(df$pid))
n.img = length(unique(df$id))

stopifnot(n.pid == n.img)

twoXtwo2 = function(x, y, dnames=c("x", "y")){
  ### could put a length(x) == length(y) check 
  nx = length(x)
  sx = sum(x)
  sy = sum(y)
  
  ### notx - number of falses in x
  notx = nx - sx
  ### need at least one joint sum - let's do the TRUE/TRUE case
  tt <- sum( x & y)
  ### x=TRUE, y= FALSE
  tf = sx - tt
  ## x= FALSE, y=TRUE
  ft = sy - tt  
  ### x= FALSE, y=FALSE
  ff = notx - ft
  
  tab = matrix(c(ff, tf, ft, tt), ncol=2)
  n = list(c("FALSE", "TRUE"), c("FALSE", "TRUE"))
  names(n) = dnames
  dimnames(tab) = n
  tab = as.table(tab)
  dim
  tab
}


my.tab = function(x, y, dnames=c("x", "y")) {
  tt = sum(x * y)
  t1=sum(x)
  t2=sum(y)
  tab = matrix(c(length(x)-t1-t2+tt,  t1-tt, t2-tt, tt), 2, 2)
  n = list(c("FALSE", "TRUE"), c("FALSE", "TRUE"))
  names(n) = dnames
  dimnames(tab) = n
  tab = as.table(tab)
  return(tab) 
}

sim <-  function(dman, dauto, dim.dman, dim.dauto){
  if ( !all(dim.dman == dim.dauto)) stop("Wrong Dimensions")
  N <- prod(dim.dman)
  
  stopifnot( ! any(is.na(dman)) )
  stopifnot( ! any(is.na(dauto)) )
  
  # system.time({
  # 	tt <- sum( dman &  dauto)
  # 	tf <- sum( dman & !dauto)
  # 	ft <- sum(!dman &  dauto)
  # 	ff <- sum(!dman & !dauto)
  # 	tab = matrix(c(ff, tf, ft, tt), ncol=2)
  # 	colnames(tab) = rownames(tab) = c("FALSE", "TRUE")
  # 	tab
  # })
  
  tab = my.tab(dman, dauto, dnames=c("dman", "dauto"))
  tt = tab["TRUE", 'TRUE']
  
  ptab = prop.table(tab)
  rowtab = prop.table(tab, 1)
  coltab = prop.table(tab, 2)
  
  accur = sum(diag(ptab))
  sens = rowtab["TRUE", "TRUE"]
  spec = rowtab["FALSE", "FALSE"]
  
  
  ab <- tt
  # estvol = sum(dauto)
  # truevol = sum(dman)
  
  estvol  = sum(tab[, "TRUE"])
  truevol = sum(tab["TRUE", ])
  
  aplusb <- (estvol + truevol)
  # aorb <- sum(dman | dauto)
  aorb = sum(tab) - tab["FALSE", "FALSE"]
  dice <- 2 * ab/aplusb
  jaccard <- ab/aorb 
  
  
  #	tab <- table(cdman, cdauto, dnn=c("dman", "dauto"))
  res <- list(dice=dice, jaccard=jaccard, 
              sens=sens, spec = spec, accur=accur, truevol = truevol,
              estvol = estvol)
  # cat("\n")
  # print(res)
  return(res)
}

# iout = "Union"
iout = "Intersection"


df$am_img = df$rimg

for (iout in c("Union", "Intersection")){
 
  out_dir = file.path(basedir, paste0(iout, "_ROI_Images"))
  
  df$rimg = file.path(out_dir, df$pid, 
                       paste0(nii.stub(df$am_img, bn=TRUE), "_", iout))

  
  splitdf = split(df, df$rimg)
  iimg = 1
  
  for (iimg in seq_along(splitdf)){
    
    dd = splitdf[[iimg]]
    rimg = dd$rimg[1]
    roi = readNIfTI(rimg, reorient=FALSE)
    roi = roi > 0
    
    hdr = dd$hdr[1]
    load(hdr)
    
    vol.roi = get_roi_vol(img = roi, dcmtables = dcmtables)
    varslice = vol.roi$varslice
    vol.roi = vol.roi$truevol
    
    results = laply(dd$ssimg, function(x){
      ss = readNIfTI(x, reorient=FALSE)
      ss = ss > 0
      truevol = get_roi_vol(img = ss, dcmtables = dcmtables)$truevol
      dman = c(roi)
      dauto = c(ss)
      dim.dman = dim(roi)
      dim.dauto = dim(ss)
      
      res = sim(dman, dauto, dim.dman, dim.dauto)	
      res$estvol = truevol
      return(res)
    }, .progress = "text")
    
    dd = cbind(dd, results)
    dd$truevol = vol.roi
    
    splitdf[[iimg]] = dd
    print(iimg)
  }
  
  ddf = do.call("rbind", splitdf)
  rownames(ddf) = NULL

  save(ddf, file=file.path(resdir, 
    paste0(iout, "_Overlap_Statistics.Rda")))
}
# 
# 