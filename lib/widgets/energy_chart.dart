import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';



class EnergyChart extends StatelessWidget {


  const EnergyChart({super.key});



  @override
  Widget build(BuildContext context){


    return chart(

      title:"Perbandingan Energi",

      value:"↓ 30.2%\nLebih hemat",

      data1:[
        80,120,90,110,85,130
      ],

      data2:[
        60,90,70,95,75,100
      ],

    );


  }





  Widget chart({

    required String title,

    required String value,

    required List<double> data1,

    required List<double> data2,


  }){


    return Container(

      padding:
      const EdgeInsets.all(15),


      decoration:BoxDecoration(

        color:Colors.white,


        borderRadius:
        BorderRadius.circular(20),


        border:
        Border.all(
          color:Colors.grey.shade300,
        ),

      ),


      child:Column(

        crossAxisAlignment:
        CrossAxisAlignment.start,


        children:[


          Row(

            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,


            children:[


              Text(

                title,

                style:
                const TextStyle(

                  fontSize:17,

                  fontWeight:
                  FontWeight.bold,

                ),

              ),



              Text(

                value,

                textAlign:
                TextAlign.right,

                style:
                const TextStyle(

                  color:Colors.green,

                  fontSize:12,

                ),

              )


            ],

          ),



          const SizedBox(height:15),



          SizedBox(

            height:220,


            child:LineChart(


              LineChartData(


                gridData:
                FlGridData(

                  show:true,

                  drawVerticalLine:false,

                ),



                titlesData:
                const FlTitlesData(

                  show:false,

                ),



                borderData:
                FlBorderData(

                  show:false,

                ),



                lineBarsData:[



                  line(

                    data1,

                    const Color(0xff0066CC),

                  ),



                  line(

                    data2,

                    const Color(0xffffb703),

                  ),


                ],


              ),



            ),

          ),




          const SizedBox(height:10),



          const Row(

            mainAxisAlignment:
            MainAxisAlignment.center,


            children:[


              Text(

                "━ Bulan lalu",

                style:
                TextStyle(

                  color:
                  Color(0xff0066CC),

                ),

              ),


              SizedBox(width:20),



              Text(

                "━ Bulan ini",

                style:
                TextStyle(

                  color:
                  Color(0xffffb703),

                ),

              )


            ],

          )



        ],


      ),


    );


  }







  LineChartBarData line(

      List<double> data,

      Color color,

      ){


    return LineChartBarData(

      spots:

      data.asMap().entries.map(

            (e)=>FlSpot(

          e.key.toDouble(),

          e.value,

        ),

      ).toList(),



      isCurved:true,


      color:color,


      barWidth:3,


      dotData:
      const FlDotData(

        show:false,

      ),



      belowBarData:
      BarAreaData(

        show:true,

        color:
        color.withOpacity(0.15),

      ),


    );


  }


}