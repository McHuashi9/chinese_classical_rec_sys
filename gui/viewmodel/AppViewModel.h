#pragma once
#include <QObject>

class AppViewModel : public QObject {
    Q_OBJECT
public:
    explicit AppViewModel(QObject *parent = nullptr);
};
