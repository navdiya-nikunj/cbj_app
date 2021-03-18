import 'package:auto_route/auto_route.dart';
import 'package:cybear_jinni/application/user_homes_list/user_homes_list_bloc.dart';
import 'package:cybear_jinni/domain/user/all_homes_of_user/all_homes_of_user_entity.dart';
import 'package:cybear_jinni/presentation/routes/app_router.gr.dart';
import 'package:flushbar/flushbar_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class HomeCardWidget extends StatelessWidget {
  const HomeCardWidget({
    Key key,
    @required this.home,
  }) : super(key: key);

  final AllHomesOfUserEntity home;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UserHomesListBloc, UserHomesListState>(
      builder: (context, state) {
        state.map(
          initial: (_) => const Text('initial'),
          loadInProgress: (_) => const Text('loadInProgress'),
          loadSuccess: (_) => const Text('loadInSuccess'),
          enterHome: (_) {
            ExtendedNavigator.of(context).replace(Routes.homePage);
          },
          loadFailure: (_) => const Text('loadFailure'),
          loadFailureEnteringHome: (_) => FlushbarHelper.createError(
            message: "Can't enter this home",
          ),
          error: (_) => const Text('error'),
        );
        return FlatButton(
          onPressed: () {
            context
                .read<UserHomesListBloc>()
                .add(UserHomesListEvent.joinExistingHome(home));
          },
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Colors.white,
                ),
                bottom: BorderSide(
                  color: Colors.white,
                ),
              ),
            ),
            height: 100,
            child: Center(
              child: ListTile(
                leading: const FaIcon(
                  FontAwesomeIcons.houseUser,
                  color: Colors.white,
                ),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      home.name.getOrCrash(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}