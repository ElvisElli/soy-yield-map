rm(list=ls())

library(ggplot2)
library(sf)
library(viridis)
library(stars)
library(dplyr)
library(tidyr)
library(readr)
library(data.table)
library(rstudioapi)
library(readxl)
library(ggrepel)
library(cowplot)

## external codes ====
source("code/plot_theme.R")

#magnitude yields====

simulated0 <- readRDS("intermediate-data/simulated-scenarios-current-df.rds") %>% as_tibble()


str(simulated0)

p1 <- simulated0 %>% 
  select(x,y,date,rel_sw_6in,rel_sw_12in,rel_sw_24in,CummRain_fromApril,swhc_24in) %>%
  filter(date==max(date)) %>%
  mutate(rel_sw_6in=rel_sw_6in*100,
         rel_sw_6in.class2=ifelse(rel_sw_6in<=40,"Dry",
                              ifelse(rel_sw_6in<=70,"Adequate","Excess")),
         rel_sw_6in.class2=as.factor(rel_sw_6in.class2),
         rel_sw_6in.class2=factor(rel_sw_6in.class2,levels = c("Dry","Adequate","Excess")),
         rel_sw_12in=rel_sw_12in*100,
         rel_sw_12in.class2=ifelse(rel_sw_12in<=40,"Dry",
                                  ifelse(rel_sw_12in<=70,"Adequate","Excess")),
         rel_sw_12in.class2=as.factor(rel_sw_12in.class2),
         rel_sw_12in.class2=factor(rel_sw_12in.class2,levels = c("Dry","Adequate","Excess")),
         rel_sw_24in=rel_sw_24in*100,
         rel_sw_24in.class2=ifelse(rel_sw_24in<=40,"Dry",
                                   ifelse(rel_sw_24in<=70,"Adequate","Excess")),
         rel_sw_24in.class2=as.factor(rel_sw_24in.class2),
         rel_sw_24in.class2=factor(rel_sw_24in.class2,levels = c("Dry","Adequate","Excess")))

# Convert to stars object
df <- st_as_stars(p1, dims = c('x', 'y'), xy = c('x', 'y'), proxy = TRUE)
st_crs(df) <- 'epsg:4326'
df <- st_transform(df, 5070)

# Load and transform Arkansas shapefile
ark <- st_read('raw-data/cropland/cb_2018_us_state_20m/cb_2018_us_state_20m.shp')
ark <- subset(ark, STUSPS == 'AR')
ark <- st_transform(ark, 5070)

# Create raster grid for biomass
df2 <- st_as_stars(st_bbox(ark), dx = 2500, dy = 2500)
df <- st_warp(df, df2, no_data_value = NA)

usa_counties <- st_read("raw-data/Elvis-Crop-Data/Arkansas_Counties_4269.shp")

coord <- read_excel("raw-data/coordinates.xlsx",sheet = "refs") %>% 
  st_as_sf(coords = c("Long", "Lat"), crs = 4326) %>% 
  st_transform(5070) %>% 
  cbind(st_coordinates(.)) %>% 
  st_drop_geometry()

last.update <- format(max(simulated0$date), "%B %d, %Y")

# Create the plot
p1 <- ggplot() +
  geom_sf(data = ark, fill = "grey90", color = "black") +  # State boundaries
  geom_stars(data = df, aes(fill = rel_sw_6in.class2)) +  # Raster data
  geom_sf(data = usa_counties, aes(geometry = geometry),fill=NA,colour="black",linewidth=0.5)+
  coord_sf(xlim = c(360000,580000)) +  # Maintain spatial coordinates
  temp+
  scale_fill_manual(
    values=c("Dry" = "#de2d26",
      "Adequate" = "#31a354",
      "Excess" = "#253494"),
    na.value = "transparent")+
  theme(axis.title = element_blank(),
        axis.text = element_blank(),
        legend.position = "right",
        legend.direction = "vertical",
        legend.key = element_rect(color = "black", linewidth = 1),
        plot.title = element_text(face = "plain"),
        legend.title = element_blank())+
  geom_point(data=coord,
             mapping = aes(x=X,y=Y),colour="black",size=3)+
  geom_text_repel(data=coord,
                   mapping = aes(x=X,y=Y,label=Station),
                   xlim = c(535000,NA),
                   ylim = c(NA,14*100000),
                   direction = "y")+
  ggtitle(paste0("Soil Water 0-6 inches\nLast update: ",last.update))

ggsave("plots/p1.tiff",width=10,height=13,units ="cm",dpi=600,compression="lzw",bg="white")

p2 <- ggplot() +
  geom_sf(data = ark, fill = "grey90", color = "black") +  # State boundaries
  geom_stars(data = df, aes(fill = rel_sw_24in.class2)) +  # Raster data
  geom_sf(data = usa_counties, aes(geometry = geometry),fill=NA,colour="black",linewidth=0.5)+
  coord_sf(xlim = c(360000,580000)) +  # Maintain spatial coordinates
  temp+
  scale_fill_manual(
    values=c("Dry" = "#de2d26",
             "Adequate" = "#31a354",
             "Excess" = "#253494"),
    na.value = "transparent")+
  theme(axis.title = element_blank(),
        axis.text = element_blank(),
        legend.position = "right",
        legend.direction = "vertical",
        legend.key = element_rect(color = "black", linewidth = 1),
        plot.title = element_text(face = "plain"),
        legend.title = element_blank())+
  geom_point(data=coord,
             mapping = aes(x=X,y=Y),colour="black",size=3)+
  geom_text_repel(data=coord,
                  mapping = aes(x=X,y=Y,label=Station),
                  xlim = c(535000,NA),
                  ylim = c(NA,14*100000),
                  direction = "y")+
  ggtitle(paste0("Soil Water 0-24 inches\nLast update: ",last.update))

ggsave("plots/p2.tiff",width=10,height=13,units ="cm",dpi=600,compression="lzw",bg="white")


p3 <- ggplot() +
  geom_sf(data = ark, fill = "grey90", color = "black") +  # State boundaries
  geom_stars(data = df, aes(fill = CummRain_fromApril/25.4)) +  # Raster data
  geom_sf(data = usa_counties, aes(geometry = geometry),fill=NA,colour="black",linewidth=0.5)+
  coord_sf(xlim = c(360000,580000)) +  # Maintain spatial coordinates
  temp+
  scale_fill_gradient(low = "red", high = "blue", na.value = "transparent")+
  theme(axis.title = element_blank(),
        axis.text = element_blank(),
        legend.position = "right",
        legend.direction = "vertical",
        legend.key = element_rect(color = "black", linewidth = 1),
        plot.title = element_text(face = "plain"),
        legend.title = element_blank())+
  geom_point(data=coord,
             mapping = aes(x=X,y=Y),colour="black",size=3)+
  geom_text_repel(data=coord,
                  mapping = aes(x=X,y=Y,label=Station),
                  xlim = c(535000,NA),
                  ylim = c(NA,14*100000),
                  direction = "y")+
  ggtitle(paste0("Cummulative rain from April 1st (inches)\nLast update: ",last.update))

ggsave("plots/p3.tiff",width=10,height=13,units ="cm",dpi=600,compression="lzw",bg="white")

p4 <- ggplot() +
  geom_sf(data = ark, fill = "grey90", color = "black") +  # State boundaries
  geom_stars(data = df, aes(fill = swhc_24in)) +  # Raster data
  geom_sf(data = usa_counties, aes(geometry = geometry),fill=NA,colour="black",linewidth=0.5)+
  coord_sf(xlim = c(360000,580000)) +  # Maintain spatial coordinates
  temp+
  scale_fill_gradient(low = "red", high = "blue", na.value = "transparent")+
  theme(axis.title = element_blank(),
        axis.text = element_blank(),
        legend.position = "right",
        legend.direction = "vertical",
        legend.key = element_rect(color = "black", linewidth = 1),
        plot.title = element_text(face = "plain"),
        legend.title = element_blank())+
  geom_point(data=coord,
             mapping = aes(x=X,y=Y),colour="black",size=3)+
  geom_text_repel(data=coord,
                  mapping = aes(x=X,y=Y,label=Station),
                  xlim = c(535000,NA),
                  ylim = c(NA,14*100000),
                  direction = "y")+
  ggtitle(paste0("Soil Water holding capacity (inches of water at 0-24 inches depth)\n"))

ggsave("plots/p4.tiff",width=10,height=13,units ="cm",dpi=600,compression="lzw",bg="white")


plots <- list(p1, p2, p3,p4)

pdf("plots/moisture.pdf", width=6,height=5)

for (p in plots) {
  print(p)
}

dev.off()


##time series

time.series <- readRDS("intermediate-data/simulated-scenarios-historical-df.rds") %>% 
  as_tibble() %>% 
  filter(Station %in% c("RRS, Rohwer","LMCRS, Marianna","PTRS, Colt",
                       "NEREC, Keiser","RREC, Stuttgart","Pratt Farm")) %>% 
  mutate(year=year(date),
         doy=yday(date))

label_dates <- seq(as.Date("2025-01-01"), as.Date("2025-12-31"), by = "60 days")
doy_breaks <- yday(label_dates)
doy_labels <- format(label_dates, "%b")

time.series  %>% 
  ggplot(aes(x=doy,y=rel_sw_12in,factor=as.factor(year))) +
  geom_line(aes(colour="Historical years"),size=0.1) +
  geom_line(data=time.series %>% filter(year==2025,
                                        date<=as.character(Sys.Date())),
            aes(colour="2025"), size = 0.5)+
  #geom_line(data=time.series %>% filter(year==2024),
  #          colour="red",size=0.3)+
  geom_line(data=time.series %>% filter(date>=as.character(Sys.Date())),
            aes(colour="Weather Forecast"), size = 0.5)+
  stat_summary(fun = mean, geom = "line", aes(group = 1,color = "Average"), size = 0.5)+ 
  #geom_hline(yintercept = 0.4, linetype = "dashed", color = "red") +
  #annotate("text", x = 0, y = 0.42, label = "Deficit Threshold", color = "red", hjust = 0, size = 4)+
  #geom_hline(yintercept = 0.7, linetype = "dashed", color = "blue") +
  #annotate("text", x = 0, y = 0.72, label = "Excess Threshold", color = "blue", hjust = 0, size = 4)+
  temp+
  scale_x_continuous(breaks = doy_breaks, labels = doy_labels)+
  scale_y_continuous(limits = c(0,1.2), breaks = c(0,0.2,0.4,0.6,0.8,1))+
  theme(axis.text.x = element_text(angle = 35, hjust = 1),
        legend.title = element_blank(),
        legend.position = "top",
        legend.direction = "horizontal")+
  facet_wrap(~Station,nrow=2)+
  labs(x=element_blank(),y="Relative soil water 0-12 inches (0-1)")+
  scale_colour_manual(values=c("Historical years"="grey",
                        "2025"="black",
                        "Weather Forecast"="red",
                        "Average"="forestgreen"))

ggsave("plots/p5.tiff",width=30,height=20,units ="cm",dpi=600,compression="lzw",bg="white")






