# emon2influx

This tool connects to an emoncms, retreives power values (from feeds with 'power' in their names). Once all data is retreived, it then inserts the updated feeds to an InfluxDB.


The solution has two 'features'.

If the feed is 'scaled' it normalizes the data, i.e. the sensor has a couple of loops, this divides with the number of loops. 

If translate is active, it then can use data in the feed name to send to InfluxDB as tag. I.e. if a feed is called: tx4_power1:Coffee_maker, it translate is incative, the used tag is tx4_power1. If active, its Coffee_maker.

