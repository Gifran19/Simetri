import 'package:flutter/material.dart';



class SummaryCard extends StatelessWidget{


  final IconData icon;

  final String title;

  final String value;



  const SummaryCard({

    super.key,

    required this.icon,

    required this.title,

    required this.value,

  });



  @override
  Widget build(BuildContext context){


    return Container(


      padding:
      const EdgeInsets.all(15),



      decoration:BoxDecoration(


        color:Colors.white,


        borderRadius:
        BorderRadius.circular(18),


      ),




      child:Column(

        crossAxisAlignment:
        CrossAxisAlignment.start,


        children:[



          CircleAvatar(

            radius:18,

            backgroundColor:
            const Color(0xffE8F8F3),


            child:Icon(

              icon,

              color:
              const Color(0xff00A896),

            ),

          ),



          const SizedBox(height:10),




          Text(

            title,

            style:
            const TextStyle(

              fontSize:12,

              color:Colors.grey,

            ),

          ),



          const SizedBox(height:5),



          Text(

            value,

            style:
            const TextStyle(

              fontWeight:
              FontWeight.bold,

              fontSize:18,

            ),

          )



        ],

      ),


    );


  }


}