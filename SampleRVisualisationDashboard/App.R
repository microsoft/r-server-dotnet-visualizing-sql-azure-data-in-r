library(shiny)
library(leaflet)
library(shinydashboard)
library(dygraphs)
library(xts)
library(RODBC)

# *** Usage Instructions: 
#   1) Restore the sample Sql Azure Database File in the SampleSqlAzureDatabaseFile folder to a SQL Azure Server in your Azure Subscription. 
#      If you don't have a SQL Azure Server yet, create one as per https://docs.microsoft.com/en-us/azure/sql-database/sql-database-get-started
#   2) Update the connectionString variable below to replate  **YourSqlAzureDatabaseHere** with the name of your SQL Azure Server
#   3) Run the solution locally with the "local" connection string uncommented. The solution will launch a ShinyApp application which connects to your SQL Azure database and visualises the data
#   4) To deploy the application to ShinyApps.io, uncomment the connection string commented as "Uncomment this line when deploying to Shiny"  and publish. 
#   5) Tailor to your own needs and data. 

ui <- dashboardPage(
  dashboardHeader(title = "Sample R Utility Dashboard"),
  dashboardSidebar(),
  dashboardBody(
  fluidRow(
    fluidRow(
      # The World Map
      leafletOutput("map"),
      # The Status Boxes
      infoBoxOutput("RenewablesPercentrageBox"),
      infoBoxOutput("NumberOfActiveCustomers"),
      infoBoxOutput("MarketPrice")
    ),
    fluidRow(
        #The charts
        dygraphOutput("Price", width = "98%")
        , dygraphOutput("Renewables", width = "98%")
    )
  ),
  p()
)
)

server <- function(input, output, session) 
    {

    ##The Connection Stirngs: These need to be different depending on whether you are running the application locally, or deploying to ShinyApps. 
    #Uncomment this line when deploying to Shiny    
    connectionString <- 'Driver=FreeTDS;TDS_Version=8.0;Server=**YourSqlAzureDatabaseHere**.database.windows.net,1433;Database=SampleEnergyUtilityDatabase;Uid=SampleDatabaseAdmin@s6l7cwnzra;Pwd=SampleEnergyPassword!;Encrypt=yes;'
    #Uncomment this line when running Locally
    #connectionString <- 'Driver=SQL Server Native Client 11.0;Server=**YourSqlAzureDatabaseHere**.database.windows.net,1433;Database=SampleEnergyUtilityDatabase;Uid=SampleDatabaseAdmin@s6l7cwnzra;Pwd=SampleEnergyPassword!;Encrypt=yes;'

    #Hardcoding some variables to demonstrate data binding from SQL Azure in R. Tailor to your own solution. See the sample SQL Azure database to see the data these relate to. 
    regionId <- 1
    regionName <- "Ireland"    

    ##Generate the Map showing customers on their location on the World Map, along with the current status
    #Retrieve the Customers data form the SQL Azure databsae to display a map. This data contains Latitude and Longitude columns. 
    conn <- odbcDriverConnect(connectionString)
    sqlQuery <- sprintf("select * from [dbo].[UtilityCustomer] WHERE [EnergyMarketId] = '%d'", regionId)
    df <- sqlQuery(conn, sqlQuery)
    customers <- df
    customers$CustomerStatus <- sprintf("Customer Name: %s. \n Status: %s", customers$CustomerFriendlyName, "Online")
    customers

    #Render the Customer geo-spacial data onto the Leaflet World Map
    output$map <- renderLeaflet({
        leaflet() %>%
        addTiles() %>%
        addMarkers(data = customers, ~ Longitude, ~ Latitude, popup = ~CustomerStatus)
    })

    ##Create the three infoBoxOutput "Status Boxes"
    #Gather data from the SQL Azure Server for the three infoBoxOutput "Status Boxes"
    MarketPriceSqlQuery <- sprintf("SELECT [CurrentMarketPrice] FROM [dbo].[EnergyMarket] WHERE EnergyMarketId = '%d'", regionId)
    dfMarketPrice <- sqlQuery(conn, MarketPriceSqlQuery)
    currentMarketPrice <- dfMarketPrice['CurrentMarketPrice']

    RenewablesPercentageSqlQuery <- sprintf("SELECT [CurrentRenewablePercentage] FROM [dbo].[EnergyMarket] WHERE EnergyMarketId = '%d'", regionId)
    dfRenewablesPercentage <- sqlQuery(conn, RenewablesPercentageSqlQuery)
    renewablePercantage <- dfRenewablesPercentage['CurrentRenewablePercentage']

    numberOfCustomers <- nrow(customers)
        
    # Renewables Box
    output$RenewablesPercentrageBox <- renderInfoBox({
        infoBox(
        "Current Renewable Energy %", paste0(renewablePercantage, "%"), icon = icon("list"),
        color = "green", fill = TRUE
      )
    })

    # Number of Customers Box
    output$NumberOfActiveCustomers <- renderInfoBox({
        infoBox(
        "Number Of Active Customers", paste0(numberOfCustomers), icon = icon("credit-card"),
        color = "purple", fill = TRUE
      )
    })

    # Current Market Price
    output$MarketPrice <- renderInfoBox({
        infoBox(
        "Current Market Price", paste0("$", currentMarketPrice), icon = icon("thumbs-up"),
        color = "yellow", fill = TRUE
      )
    })

    ##Generate the data charts displaying time series data
    #Time Series Price Data
    gridDateSqlQuery <- sprintf("SELECT TOP (1000) [EnergyMarketId], [DateTime], [MarketPrice] , [AveragePrice] FROM [dbo].[EnergyMarketPrice] WHERE [EnergyMarketId] = '%d' ORDER BY [DateTime] DESC", regionId)    
    dbResults <- sqlQuery(conn, gridDateSqlQuery)
    dataset <- dbResults
    datasetAsArray <- cbind(dataset)

    priceArray <- datasetAsArray[, c("DateTime", "MarketPrice", "AveragePrice")]
    priceArrayAsXts <- xts(priceArray[, -1], order.by = priceArray[, 1])
    output$Price <- renderDygraph({
        dygraph(priceArrayAsXts, main = "Electricity Market Prices") %>%
        dySeries("MarketPrice", label = "MarketPrice", fillGraph = TRUE) %>%
        dySeries("AveragePrice", label = "AveragePrice", drawPoints = TRUE, strokePattern = "dashed") %>%
        dyOptions(stackedGraph = FALSE) %>%
    dyRangeSelector(height = 20)
    })

    #Time Series Renewables Data
    renewablesSqlQuery <- sprintf("SELECT TOP (1000) [EnergyMarketId], [DateTime], [RenewablesPercentage], [WindSpeed_Kmph] FROM [dbo].[EnergyMarketRenewablesAndWindSpeed] WHERE [EnergyMarketId] = '%d' ORDER BY [DateTime] DESC", regionId)
    dbRenewablesResults <- sqlQuery(conn, renewablesSqlQuery)
    renewablesDataset <- dbRenewablesResults
    renewablesDatasetAsArray <- cbind(renewablesDataset)

    renewablesArray <- renewablesDatasetAsArray[, c("DateTime", "RenewablesPercentage", "WindSpeed_Kmph")]
    renewablesArrayAsXts <- xts(renewablesArray[, -1], order.by = renewablesArray[, 1])
    output$Renewables <- renderDygraph({
        dygraph(renewablesArrayAsXts, main = "Renewable Percentage and Wind Speeds") %>%
        dySeries("RenewablesPercentage", label = "Renewable Percentage", fillGraph = TRUE) %>%
        dySeries("WindSpeed_Kmph", label = "WindSpeed Kmph", drawPoints = TRUE, strokePattern = "dashed") %>%
        dyOptions(stackedGraph = FALSE) %>%
        dyRangeSelector(height = 20)
    })

    close(conn) # Close the connection
}

shinyApp(ui, server)
