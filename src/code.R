# import library
library(ggplot2)
library(shiny)
library(leaflet)
library(dplyr)
library(rgdal)

# returns string w/o leading or trailing whitespace
trim <- function (x) gsub("^\\s+|\\s+$", "", x)

# Contents
content1 <- '<p>Australia is one of the most liveable countries and there are many people intend to migrate to 
this country. The purpose of this project is to find a data insight and present an effect of Overseas Migration to Australia in different aspects.
A targeted client will be specialised users and general people who understand basic bar chart, line graph, and map.
These questions below will assist and guide a data exploration process and represent in an interactive tool on website.</p>
<p><h4>Questions:</h4>
1. Does overseas migration affect an Australia economy?</br>
2. What is the migration population in each state?
</p>'


##### State section
# load geo data
df_geo <- read.csv("states geo.csv",  header = TRUE, sep=',')

# prepare pop_state
state_list <- c("Australian Capital Territory","New South Wales","Northern Territory","Queensland"
                ,"South Australia","Tasmania", "Victoria","Western Australia")
df_state <- read.csv("states pop.csv",  header = TRUE, sep=',')
df_state$Year <- format(as.Date(df_state$Quater,format="%d/%m/%Y"), '%Y')
df_state$State <- trim(as.character(df_state$State))
#df_state <- df_state %>% filter(State!="Australian Capital Territory")

df_state <- df_state %>% 
  group_by(Year, State) %>% 
  summarise(Number.of.change = sum(Number.of.change),
            Net.Interstate.Migration = sum(Net.Interstate.Migration),
            Net.Overseas.Migration = sum(Net.Overseas.Migration)) %>%
  mutate(Cum.Number.of.change = cumsum(Number.of.change)) 

# join pop_state and geo
df_state <- merge(df_state, df_geo, by = 'State', all = TRUE)


# load state_gdp
df_state_gdp <- read.csv("state gdp.csv",  header = TRUE, sep=',')
df_state_gdp$State <- trim( as.character(df_state_gdp$State))
df_state_gdp$Year <- format(as.Date(df_state_gdp$Date,format="%d/%m/%Y"), '%Y')
df_state_gdp <- df_state_gdp %>%
  group_by(Year,State) %>%
  summarise(GDP.value = sum(GDP.value),
            GDP.percent = sum(GDP.percent)) %>%
  mutate(Cum.GDP.value = cumsum(GDP.value)) 

# join state_gdp with pop_state and geo
df_state <- merge(df_state, df_state_gdp, by = c('Year','State'), all = TRUE)

# load shape file
states <- readOGR("AU shp/States Map.shp",layer="States Map", GDAL1_integer64_policy = TRUE)
neStates <- subset(states, states$NAME %in% state_list)


##### Overal section
df_au_gdp <- read.csv("Evolution- Annual GDP Australia.csv",  header = TRUE, sep=',')
df_au_pop <- read.csv("aus pop.csv",  header = TRUE, sep=',')

df_au_gdp$GDP.Growth <- as.numeric(sub('%', '', df_au_gdp$GDP.Growth))
df_au_gdp$Annual.GDP <- as.numeric(gsub(',', '', df_au_gdp$Annual.GDP))

df_aus <- merge(df_au_gdp, df_au_pop, by = 'Year', all = TRUE)


# Shiny UI
ui <- fluidPage(
  HTML('<div style="position:absolute; left:70px; right:70px; 
        background-color: white; margin:10px;"><div id="xxx" style=" margin:20px;">'),
  h1('Australian Migration and GDP'),
  fluidRow(column(width=12, HTML(content1))
           ),
  fluidRow(column(width=7, plotOutput('auPlot')),
           column(width=5, leafletOutput('mymap'))),
  fluidRow(column(width=7, plotOutput('statePlot')),
           column(width=5, 
                  sliderInput('input_year','Year', 1990, 2019, 2019, 1),
                  checkboxGroupInput('input_states', 'States', state_list, state_list),
                  actionLink('selectall','Select All'), 
                  HTML('&nbsp;'),
                  actionLink('unSelectall','Unselect All'))
           )
  ,HTML('</div></div>')
  ,tags$head(tags$style("body {background-color: grey; }"))
)

# Shiny server
server <- function(input, output, session) {
  ##### overal ####
  output$auPlot <- reactivePlot(function(){
    df_filter <- df_aus %>% filter(Year <= input$input_year )
    pl <- ggplot(df_filter) + 
      geom_bar(aes(x=Year,y=Annual.GDP /5000, group = 1),stat="identity", color="darkblue", fill="lightblue") +
      geom_line(aes(x=Year, y=Net.Overseas.Migration),stat="identity", size = 1.0, colour="red") +
      geom_point(aes(x = Year, y = Net.Overseas.Migration, color = 'lightblue'), size = 1.0, inherit.aes = FALSE) +
      geom_point(aes(x = Year, y = Net.Overseas.Migration, color = 'black'), size = 1.0, inherit.aes = FALSE) +
      scale_y_continuous(sec.axis = sec_axis(~.*4.66667, name = "Australian Overseas Migration (K)")) +
      labs(title='Australian Migration and GDP', y = "Gross Domestic Product (B USD)")+ 
      scale_color_identity(guide = "legend",name = "", labels = c("Migration", "GDP"))+ 
      theme(legend.position="top")
    pl
  })
  
  ##### States ####
  output$statePlot <- reactivePlot(function(){
    df_filter <- df_state %>% filter(Year <= input$input_year )
    df_filter$Year <- as.numeric(df_filter$Year)
    df_filter <- filter(df_filter, State %in% input$input_states)
    
    pl <- ggplot(data=df_filter, aes(x=Year, y=Net.Overseas.Migration, group=State)) +
      geom_line(aes(color=State), size = 1.0)+
      geom_point(aes(color=State)) + theme(legend.position="top")+
      labs(x ="Year", y = "Overseas migration each state (K)")
    pl
  })
  
  
  ##### map #####
  get_df_state_filter <- reactive({
    df_state %>% filter(Year==input$input_year)
  })
  
  # create leaflet map
  output$mymap <- renderLeaflet({ 
    # filter
    df_state_filter <- df_state %>% filter(Year=="2019" )
    
    # set icons pop
    popIcons <- get_popIcons(df_state_filter)
    
    # set icons GDP
    gdpIcons <- get_gdpIcons(df_state_filter)
    
    # integrate data with shape file
    df_state_filter$State <- ordered(df_state_filter$State, c("New South Wales","Victoria",
                                                              "Queensland","South Australia", "Western Australia","Tasmania",
                                                              "Northern Territory","Australian Capital Territory")
    )
    neStates$Net.Interstate.Migration <- df_state_filter[order(df_state_filter$State), 'Net.Interstate.Migration']
    neStates$Net.Overseas.Migration <- df_state_filter[order(df_state_filter$State), 'Net.Overseas.Migration']
    neStates$Number.of.change <- df_state_filter[order(df_state_filter$State), 'Number.of.change']
    neStates$GDP.value <- df_state_filter[order(df_state_filter$State), 'GDP.value']
    neStates$GDP.GDP.percent <- df_state_filter[order(df_state_filter$State), 'GDP.percent']
    
    # bind labels
    map_labels <- get_map_labels(neStates)
    
    html_legend <- "<div style='font-size:10px; background'><p>
      <img src='https://i.ibb.co/Zdtfz2y/green-arrow.png' width='15px'>
      <img src='https://i.ibb.co/NtmL9HV/red-arrow.png' width='15px'>
      Increase/Decrease Migration population<br/></p>
      <img src='https://i.ibb.co/JcQrhCw/green-dollar.png' width='15px'>
      <img src='https://i.ibb.co/2cGPdMp/red-dollar.png' width='15px'>
      Increase/Decrease GDP</div>
    "
    
    # draw a base map
    leaflet(data = df_state_filter) %>%
      addProviderTiles("Esri.WorldGrayCanvas") %>%
      addMarkers(df_state_filter, lng = ~long, lat = ~lat+1, icon = popIcons) %>%
      addMarkers(df_state_filter, lng = ~long, lat = ~lat-1, icon = gdpIcons) %>%
      addPolygons(data = neStates,color = "#444444", weight = 1, smoothFactor = 0.5,
                  opacity = 1.0, fillOpacity = 0.5,
                  fillColor = "white",
                  highlightOptions = highlightOptions(color = "orange", weight = 2,
                                                      bringToFront = TRUE),
                  label = map_labels,
                  labelOptions = labelOptions(
                    style = list("font-weight" = "normal", padding = "3px 8px"),
                    textsize = "15px",
                    direction = "auto")) %>%
      addControl(html = html_legend, position = "topright")
    })
  
  observe({
    # update data
    df_state_filter <- get_df_state_filter()
    popIcons <- get_popIcons(df_state_filter)
    gdpIcons <- get_gdpIcons(df_state_filter)
    
    # update map labels
    df_state_filter$State <- ordered(df_state_filter$State, c("New South Wales","Victoria",
                                                              "Queensland","South Australia", "Western Australia","Tasmania",
                                                              "Northern Territory","Australian Capital Territory")
    )
    neStates$Net.Interstate.Migration <- df_state_filter[order(df_state_filter$State), 'Net.Interstate.Migration']
    neStates$Net.Overseas.Migration <- df_state_filter[order(df_state_filter$State), 'Net.Overseas.Migration']
    neStates$Number.of.change <- df_state_filter[order(df_state_filter$State), 'Number.of.change']
    neStates$GDP.value <- df_state_filter[order(df_state_filter$State), 'GDP.value']
    neStates$GDP.GDP.percent <- df_state_filter[order(df_state_filter$State), 'GDP.percent']
    # bind labels
    map_labels <- get_map_labels(neStates)
    
    # draw a map
    leafletProxy("mymap", data = df_state_filter) %>%
      clearMarkers() %>%
      addMarkers(df_state_filter, lng = ~long, lat = ~lat+1, icon = popIcons) %>%
      addMarkers(df_state_filter, lng = ~long, lat = ~lat-2, icon = gdpIcons) %>%
      addPolygons(data = neStates,color = "#444444", weight = 1, smoothFactor = 0.5,
                  opacity = 1.0, fillOpacity = 0.5,
                  fillColor = "white",
                  highlightOptions = highlightOptions(color = "orange", weight = 2,
                                                      bringToFront = TRUE),
                  label = map_labels,
                  labelOptions = labelOptions(
                    style = list("font-weight" = "normal", padding = "3px 8px"),
                    textsize = "15px",
                    direction = "auto")) 
  })
  
  get_popIcons <- function(df_state_filter){
    min_w_pop <- 10
    ratio_w_pop <- 50 / max(df_state_filter$Number.of.change)
    popIcons <- icons(
      iconUrl = ifelse(df_state_filter$Number.of.change > 0,
                       "image/green-arrow.png",
                       "image/red-arrow.png"
      )
      ,iconWidth = ifelse(ratio_w_pop* df_state_filter$Number.of.change < min_w_pop,
                          min_w_pop,
                          ratio_w_pop* df_state_filter$Number.of.change)
      , iconHeight = 20
    )
    return(popIcons)
  }
  
  get_gdpIcons <- function(df_state_filter){
    gdpIcons <- icons(
      iconUrl = ifelse(df_state_filter$GDP.percent > 0,
                       "image/green-dollar.png",
                       "image/red-dollar.png"
      )
      ,iconWidth = ifelse(abs(df_state_filter$GDP.percent) <= 1,
                          10,
                          ifelse(abs(df_state_filter$GDP.percent) <= 2,
                                 20,30))
      , iconHeight = 15
    )
    return(gdpIcons)
  }
  
  get_map_labels <- function(neStates){
    map_labels <- sprintf(
      "<div style='font-size:12px;'>
          <strong>%s (%s)</strong>
          <br/>Total migration %gK people
          <br/>Interstate migration %gK people
          <br/>Overseas migration %gK people
          <br/>GDP %g%% $%gM
      </div>"
      ,
      neStates$NAME, input$input_year, neStates$Number.of.change, neStates$Net.Interstate.Migration
      , neStates$Net.Overseas.Migration, neStates$GDP.GDP.percent, neStates$GDP.value
    ) %>% lapply(htmltools::HTML)
    return(map_labels)
  }
  
  observe({
    if(input$selectall == 0) 
      return(NULL) 
    else
      updateCheckboxGroupInput(session,'input_states','States',choices=state_list,selected=state_list)
  })
  
  observe({
    if(input$unSelectall == 0) 
      return(NULL)
    else
      updateCheckboxGroupInput(session,'input_states','States',choices=state_list,selected=NULL)
  })
}

# Run Shiny App
shinyApp(ui, server)



