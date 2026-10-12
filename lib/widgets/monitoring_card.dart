import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/device_data.dart';


class MonitoringCard extends StatelessWidget {

  final DeviceData device;


  const MonitoringCard({

    super.key,

    required this.device,

  });


  @override
  Widget build(BuildContext context) {


    return Container(

      height:300,

      padding:
      const EdgeInsets.all(20),


      decoration:BoxDecoration(

        color:Colors.white,

        borderRadius:
        BorderRadius.circular(20),


        border:
        Border.all(

          color:
          Colors.grey.shade300,

        ),

      ),



      child:Column(

        children:[


          const Text(

            "Monitoring saat ini",

            style:TextStyle(

              fontSize:18,

              fontWeight:
              FontWeight.bold,

            ),

          ),



          const SizedBox(height:20),



          Expanded(

            child:Stack(

              children:[



                // VOLTAGE KIRI

                Positioned(

                  left:0,

                  top:20,

                  child:gauge(

                    value:
                    "${device.voltage} V",

                    title:
                    "Voltage",

                    progress:
                    0.85,

                  ),

                ),





                // CURRENT KANAN

                Positioned(

                  right:0,

                  top:20,

                  child:gauge(

                    value:
                    "${device.current} A",

                    title:
                    "Current",

                    progress:
                    0.25,

                  ),

                ),





                // POWER TENGAH BAWAH

                Positioned(

                  bottom:0,

                  left:0,

                  right:0,


                  child:gauge(

                    value:
                    "${device.power} W",

                    title:
                    "Power",

                    progress:
                    0.35,

                  ),

                ),



              ],

            ),

          )



        ],

      ),


    );


  }







  Widget gauge({

    required String value,

    required String title,

    required double progress,

  }){


    return Column(

      children:[


        SizedBox(

          width:85,

          height:85,


          child:Stack(

            alignment:
            Alignment.center,


            children:[



              PieChart(

                PieChartData(


                  startDegreeOffset:
                  -90,


                  sectionsSpace:
                  0,


                  centerSpaceRadius:
                  34,



                  sections:[



                    PieChartSectionData(

                      value:
                      progress*100,


                      color:
                      const Color(0xff00A896),


                      radius:9,


                      showTitle:false,

                    ),



                    PieChartSectionData(

                      value:
                      100-(progress*100),


                      color:
                      const Color(0xffE8EDF2),


                      radius:9,


                      showTitle:false,

                    ),



                  ],


                ),

              ),




              Text(

                value,

                style:
                const TextStyle(

                  fontSize:11,

                  fontWeight:
                  FontWeight.bold,

                ),

              )



            ],

          ),

        ),




        const SizedBox(height:6),



        Text(

          title,

          style:
          TextStyle(

            fontSize:12,

            color:
            Colors.grey.shade600,

          ),

        )


      ],


    );


  }


}